use tokio::io::AsyncWriteExt;

/// Split an Annex-B byte stream into individual NAL units.
///
/// Handles both 3-byte (00 00 01) and 4-byte (00 00 00 01) start codes.
/// Returns slices of NAL data without the start code prefixes.
pub(crate) fn split_nals(data: &[u8]) -> Vec<&[u8]> {
    let mut nals = Vec::new();
    let mut i = 0;
    let len = data.len();

    // Find first start code
    let mut nal_start = None;

    while i < len {
        if i + 3 <= len && data[i] == 0x00 && data[i + 1] == 0x00 && data[i + 2] == 0x01 {
            // 3-byte start code — but check for 4-byte variant
            let sc_len = if i > 0 && data[i - 1] == 0x00 { 0 } else { 3 };
            if let Some(start) = nal_start {
                // End of previous NAL
                let end = if sc_len == 0 { i - 1 } else { i };
                if end > start {
                    nals.push(&data[start..end]);
                }
            }
            nal_start = Some(i + 3);
            if sc_len == 0 {
                // We already consumed the 00, advance past 00 01
                i += 3;
            } else {
                i += 3;
            }
        } else if i + 4 <= len
            && data[i] == 0x00
            && data[i + 1] == 0x00
            && data[i + 2] == 0x00
            && data[i + 3] == 0x01
        {
            if let Some(start) = nal_start {
                if i > start {
                    nals.push(&data[start..i]);
                }
            }
            nal_start = Some(i + 4);
            i += 4;
        } else {
            i += 1;
        }
    }

    // Last NAL
    if let Some(start) = nal_start {
        if start < len {
            nals.push(&data[start..len]);
        }
    }

    nals
}

/// Convert Annex-B NALs to AVCC format (4-byte big-endian length prefix per NAL).
pub(crate) fn annex_b_to_avcc(annex_b: &[u8]) -> Vec<u8> {
    let nals = split_nals(annex_b);
    let total_size: usize = nals.iter().map(|n| 4 + n.len()).sum();
    let mut out = Vec::with_capacity(total_size);
    for nal in nals {
        let len = nal.len() as u32;
        out.extend_from_slice(&len.to_be_bytes());
        out.extend_from_slice(nal);
    }
    out
}

/// Exp-Golomb unsigned integer decoder operating on a bit stream.
struct BitReader<'a> {
    data: &'a [u8],
    byte_offset: usize,
    bit_offset: u8, // 0..8, bits consumed in current byte
}

impl<'a> BitReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self {
            data,
            byte_offset: 0,
            bit_offset: 0,
        }
    }

    fn read_bit(&mut self) -> u32 {
        if self.byte_offset >= self.data.len() {
            return 0;
        }
        let bit = (self.data[self.byte_offset] >> (7 - self.bit_offset)) & 1;
        self.bit_offset += 1;
        if self.bit_offset == 8 {
            self.bit_offset = 0;
            self.byte_offset += 1;
        }
        u32::from(bit)
    }

    fn read_bits(&mut self, n: u32) -> u32 {
        let mut val = 0u32;
        for _ in 0..n {
            val = (val << 1) | self.read_bit();
        }
        val
    }

    fn read_ue(&mut self) -> u32 {
        let mut leading_zeros = 0u32;
        while self.read_bit() == 0 {
            leading_zeros += 1;
            if leading_zeros > 31 {
                return 0;
            }
        }
        if leading_zeros == 0 {
            return 0;
        }
        let suffix = self.read_bits(leading_zeros);
        (1 << leading_zeros) - 1 + suffix
    }

    fn read_se(&mut self) -> i32 {
        let val = self.read_ue();
        if val.is_multiple_of(2) {
            -(val as i32 / 2)
        } else {
            (val as i32 + 1) / 2
        }
    }
}

/// Parse an SPS NAL unit (without the NAL header byte) to extract width and height.
fn parse_sps_dimensions(sps: &[u8]) -> (u32, u32) {
    if sps.is_empty() {
        return (0, 0);
    }

    // sps[0] is the NAL header byte (0x67 for SPS). Skip it.
    let rbsp = &sps[1..];
    if rbsp.len() < 4 {
        return (0, 0);
    }

    let profile_idc = rbsp[0];
    // rbsp[1] = constraint flags / profile_compat
    let level_idc = rbsp[2];
    let _ = level_idc;

    let mut br = BitReader::new(&rbsp[3..]);
    let _seq_parameter_set_id = br.read_ue();

    let mut chroma_format_idc = 1u32; // default

    if matches!(
        profile_idc,
        100 | 110 | 122 | 244 | 44 | 83 | 86 | 118 | 128 | 138 | 139 | 134 | 135
    ) {
        chroma_format_idc = br.read_ue();
        if chroma_format_idc == 3 {
            let _separate_colour_plane_flag = br.read_bits(1);
        }
        let _bit_depth_luma_minus8 = br.read_ue();
        let _bit_depth_chroma_minus8 = br.read_ue();
        let _qpprime_y_zero_transform_bypass_flag = br.read_bits(1);
        let seq_scaling_matrix_present_flag = br.read_bits(1);
        if seq_scaling_matrix_present_flag != 0 {
            let count = if chroma_format_idc != 3 { 8 } else { 12 };
            for i in 0..count {
                let present = br.read_bits(1);
                if present != 0 {
                    let size = if i < 6 { 16 } else { 64 };
                    let mut last_scale = 8i32;
                    let mut next_scale = 8i32;
                    for _ in 0..size {
                        if next_scale != 0 {
                            let delta = br.read_se();
                            next_scale = (last_scale + delta + 256) % 256;
                        }
                        last_scale = if next_scale == 0 {
                            last_scale
                        } else {
                            next_scale
                        };
                    }
                }
            }
        }
    }

    let _log2_max_frame_num_minus4 = br.read_ue();
    let pic_order_cnt_type = br.read_ue();

    if pic_order_cnt_type == 0 {
        let _log2_max_pic_order_cnt_lsb_minus4 = br.read_ue();
    } else if pic_order_cnt_type == 1 {
        let _delta_pic_order_always_zero_flag = br.read_bits(1);
        let _offset_for_non_ref_pic = br.read_se();
        let _offset_for_top_to_bottom_field = br.read_se();
        let num_ref_frames_in_pic_order_cnt_cycle = br.read_ue();
        for _ in 0..num_ref_frames_in_pic_order_cnt_cycle {
            let _offset = br.read_se();
        }
    }

    let _max_num_ref_frames = br.read_ue();
    let _gaps_in_frame_num_value_allowed_flag = br.read_bits(1);

    let pic_width_in_mbs_minus1 = br.read_ue();
    let pic_height_in_map_units_minus1 = br.read_ue();
    let frame_mbs_only_flag = br.read_bits(1);

    if frame_mbs_only_flag == 0 {
        let _mb_adaptive_frame_field_flag = br.read_bits(1);
    }

    let _direct_8x8_inference_flag = br.read_bits(1);
    let frame_cropping_flag = br.read_bits(1);

    let (mut crop_left, mut crop_right, mut crop_top, mut crop_bottom) = (0u32, 0u32, 0u32, 0u32);
    if frame_cropping_flag != 0 {
        crop_left = br.read_ue();
        crop_right = br.read_ue();
        crop_top = br.read_ue();
        crop_bottom = br.read_ue();
    }

    let sub_width_c: u32 = match chroma_format_idc {
        1 => 2,
        2 => 2,
        3 => 1,
        _ => 2,
    };
    let sub_height_c: u32 = match chroma_format_idc {
        1 => 2,
        2 => 1,
        3 => 1,
        _ => 2,
    };

    let crop_unit_x = if chroma_format_idc == 0 {
        1
    } else {
        sub_width_c
    };
    let crop_unit_y = if chroma_format_idc == 0 {
        2 - frame_mbs_only_flag
    } else {
        sub_height_c * (2 - frame_mbs_only_flag)
    };

    let width = (pic_width_in_mbs_minus1 + 1) * 16 - crop_unit_x * (crop_left + crop_right);
    let height = (2 - frame_mbs_only_flag) * (pic_height_in_map_units_minus1 + 1) * 16
        - crop_unit_y * (crop_top + crop_bottom);

    (width, height)
}

// ── MP4 box helpers ──────────────────────────────────────────────────────

fn write_box(out: &mut Vec<u8>, box_type: [u8; 4], content: &[u8]) {
    let size = (8 + content.len()) as u32;
    out.extend_from_slice(&size.to_be_bytes());
    out.extend_from_slice(&box_type);
    out.extend_from_slice(content);
}

/// Build a box that wraps child boxes (container box).
fn build_container_box(box_type: [u8; 4], children: &[u8]) -> Vec<u8> {
    let size = (8 + children.len()) as u32;
    let mut out = Vec::with_capacity(size as usize);
    out.extend_from_slice(&size.to_be_bytes());
    out.extend_from_slice(&box_type);
    out.extend_from_slice(children);
    out
}

fn build_full_box(box_type: [u8; 4], version: u8, flags: u32, content: &[u8]) -> Vec<u8> {
    let size = (12 + content.len()) as u32;
    let mut out = Vec::with_capacity(size as usize);
    out.extend_from_slice(&size.to_be_bytes());
    out.extend_from_slice(&box_type);
    out.push(version);
    let flag_bytes = flags.to_be_bytes();
    out.extend_from_slice(&flag_bytes[1..4]);
    out.extend_from_slice(content);
    out
}

// ── Mp4Muxer ─────────────────────────────────────────────────────────────

pub struct Mp4Muxer {
    sps: Option<Vec<u8>>,
    pps: Option<Vec<u8>>,
    sequence_number: u32,
}

impl Default for Mp4Muxer {
    fn default() -> Self {
        Self::new()
    }
}

impl Mp4Muxer {
    pub fn new() -> Self {
        Self {
            sps: None,
            pps: None,
            sequence_number: 0,
        }
    }

    pub fn set_sps_pps(&mut self, sps: Vec<u8>, pps: Vec<u8>) {
        self.sps = Some(sps);
        self.pps = Some(pps);
    }

    /// Build the ftyp + moov init segment for fMP4.
    pub fn build_init_segment(&self, sps: &[u8], pps: &[u8]) -> Vec<u8> {
        let (width, height) = parse_sps_dimensions(sps);
        let mut out = Vec::with_capacity(512);

        // ── ftyp ──
        {
            let mut content = Vec::new();
            content.extend_from_slice(b"isom"); // major_brand
            content.extend_from_slice(&0x200u32.to_be_bytes()); // minor_version
            content.extend_from_slice(b"isom"); // compatible brands
            content.extend_from_slice(b"iso2");
            content.extend_from_slice(b"avc1");
            content.extend_from_slice(b"mp41");
            write_box(&mut out, *b"ftyp", &content);
        }

        // ── moov ──
        let moov = {
            let mut children = Vec::new();

            // mvhd (version 0)
            {
                let mut c = Vec::new();
                c.extend_from_slice(&0u32.to_be_bytes()); // creation_time
                c.extend_from_slice(&0u32.to_be_bytes()); // modification_time
                c.extend_from_slice(&90000u32.to_be_bytes()); // timescale
                c.extend_from_slice(&0u32.to_be_bytes()); // duration
                c.extend_from_slice(&0x00010000u32.to_be_bytes()); // rate (1.0)
                c.extend_from_slice(&0x0100u16.to_be_bytes()); // volume (1.0)
                c.extend_from_slice(&[0u8; 10]); // reserved
                                                 // identity matrix (9 * 4 = 36 bytes)
                let matrix: [u32; 9] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];
                for &m in &matrix {
                    c.extend_from_slice(&m.to_be_bytes());
                }
                c.extend_from_slice(&[0u8; 24]); // pre_defined
                c.extend_from_slice(&2u32.to_be_bytes()); // next_track_ID
                let mvhd = build_full_box(*b"mvhd", 0, 0, &c);
                children.extend_from_slice(&mvhd);
            }

            // trak
            {
                let mut trak_children = Vec::new();

                // tkhd (version 0, flags=0x03)
                {
                    let mut c = Vec::new();
                    c.extend_from_slice(&0u32.to_be_bytes()); // creation_time
                    c.extend_from_slice(&0u32.to_be_bytes()); // modification_time
                    c.extend_from_slice(&1u32.to_be_bytes()); // track_ID
                    c.extend_from_slice(&0u32.to_be_bytes()); // reserved
                    c.extend_from_slice(&0u32.to_be_bytes()); // duration
                    c.extend_from_slice(&[0u8; 8]); // reserved
                    c.extend_from_slice(&0u16.to_be_bytes()); // layer
                    c.extend_from_slice(&0u16.to_be_bytes()); // alternate_group
                    c.extend_from_slice(&0u16.to_be_bytes()); // volume (0 for video)
                    c.extend_from_slice(&[0u8; 2]); // reserved
                    let matrix: [u32; 9] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];
                    for &m in &matrix {
                        c.extend_from_slice(&m.to_be_bytes());
                    }
                    // width and height in 16.16 fixed point
                    c.extend_from_slice(&(width << 16).to_be_bytes());
                    c.extend_from_slice(&(height << 16).to_be_bytes());
                    let tkhd = build_full_box(*b"tkhd", 0, 0x03, &c);
                    trak_children.extend_from_slice(&tkhd);
                }

                // mdia
                {
                    let mut mdia_children = Vec::new();

                    // mdhd (version 0)
                    {
                        let mut c = Vec::new();
                        c.extend_from_slice(&0u32.to_be_bytes()); // creation_time
                        c.extend_from_slice(&0u32.to_be_bytes()); // modification_time
                        c.extend_from_slice(&90000u32.to_be_bytes()); // timescale
                        c.extend_from_slice(&0u32.to_be_bytes()); // duration
                        c.extend_from_slice(&0x55C4u16.to_be_bytes()); // language: "und" (undetermined)
                        c.extend_from_slice(&0u16.to_be_bytes()); // pre_defined
                        let mdhd = build_full_box(*b"mdhd", 0, 0, &c);
                        mdia_children.extend_from_slice(&mdhd);
                    }

                    // hdlr
                    {
                        let mut c = Vec::new();
                        c.extend_from_slice(&0u32.to_be_bytes()); // pre_defined
                        c.extend_from_slice(b"vide"); // handler_type
                        c.extend_from_slice(&[0u8; 12]); // reserved
                        c.extend_from_slice(b"VideoHandler\0"); // name (null-terminated)
                        let hdlr = build_full_box(*b"hdlr", 0, 0, &c);
                        mdia_children.extend_from_slice(&hdlr);
                    }

                    // minf
                    {
                        let mut minf_children = Vec::new();

                        // vmhd (version 0, flags=1)
                        {
                            let mut c = Vec::new();
                            c.extend_from_slice(&0u16.to_be_bytes()); // graphicsmode
                            c.extend_from_slice(&[0u8; 6]); // opcolor
                            let vmhd = build_full_box(*b"vmhd", 0, 1, &c);
                            minf_children.extend_from_slice(&vmhd);
                        }

                        // dinf > dref > url
                        {
                            let url_box = build_full_box(*b"url ", 0, 1, &[]);
                            let mut dref_content = Vec::new();
                            dref_content.extend_from_slice(&1u32.to_be_bytes()); // entry_count
                            dref_content.extend_from_slice(&url_box);
                            let dref = build_full_box(*b"dref", 0, 0, &dref_content);
                            let dinf = build_container_box(*b"dinf", &dref);
                            minf_children.extend_from_slice(&dinf);
                        }

                        // stbl
                        {
                            let mut stbl_children = Vec::new();

                            // stsd > avc1 > avcC
                            {
                                let avcc = Self::build_avcc(sps, pps);

                                let mut avc1 = Vec::new();
                                // SampleEntry fields
                                avc1.extend_from_slice(&[0u8; 6]); // reserved
                                avc1.extend_from_slice(&1u16.to_be_bytes()); // data_reference_index
                                                                             // VisualSampleEntry fields
                                avc1.extend_from_slice(&0u16.to_be_bytes()); // pre_defined
                                avc1.extend_from_slice(&0u16.to_be_bytes()); // reserved
                                avc1.extend_from_slice(&[0u8; 12]); // pre_defined
                                avc1.extend_from_slice(&(width as u16).to_be_bytes());
                                avc1.extend_from_slice(&(height as u16).to_be_bytes());
                                avc1.extend_from_slice(&0x00480000u32.to_be_bytes()); // horiz resolution 72 dpi
                                avc1.extend_from_slice(&0x00480000u32.to_be_bytes()); // vert resolution 72 dpi
                                avc1.extend_from_slice(&0u32.to_be_bytes()); // reserved
                                avc1.extend_from_slice(&1u16.to_be_bytes()); // frame_count
                                avc1.extend_from_slice(&[0u8; 32]); // compressorname
                                avc1.extend_from_slice(&0x0018u16.to_be_bytes()); // depth
                                avc1.extend_from_slice(&0xFFFFu16.to_be_bytes()); // pre_defined = -1
                                                                                  // Append avcC box
                                avc1.extend_from_slice(&avcc);

                                // Wrap in avc1 box (note: avc1 is NOT a full box)
                                let avc1_box = build_container_box(*b"avc1", &avc1);

                                let mut stsd_content = Vec::new();
                                stsd_content.extend_from_slice(&1u32.to_be_bytes()); // entry_count
                                stsd_content.extend_from_slice(&avc1_box);
                                let stsd = build_full_box(*b"stsd", 0, 0, &stsd_content);
                                stbl_children.extend_from_slice(&stsd);
                            }

                            // stts
                            {
                                let mut c = Vec::new();
                                c.extend_from_slice(&0u32.to_be_bytes()); // entry_count
                                let stts = build_full_box(*b"stts", 0, 0, &c);
                                stbl_children.extend_from_slice(&stts);
                            }

                            // stsc
                            {
                                let mut c = Vec::new();
                                c.extend_from_slice(&0u32.to_be_bytes());
                                let stsc = build_full_box(*b"stsc", 0, 0, &c);
                                stbl_children.extend_from_slice(&stsc);
                            }

                            // stsz
                            {
                                let mut c = Vec::new();
                                c.extend_from_slice(&0u32.to_be_bytes()); // sample_size
                                c.extend_from_slice(&0u32.to_be_bytes()); // sample_count
                                let stsz = build_full_box(*b"stsz", 0, 0, &c);
                                stbl_children.extend_from_slice(&stsz);
                            }

                            // stco
                            {
                                let mut c = Vec::new();
                                c.extend_from_slice(&0u32.to_be_bytes()); // entry_count
                                let stco = build_full_box(*b"stco", 0, 0, &c);
                                stbl_children.extend_from_slice(&stco);
                            }

                            let stbl = build_container_box(*b"stbl", &stbl_children);
                            minf_children.extend_from_slice(&stbl);
                        }

                        let minf = build_container_box(*b"minf", &minf_children);
                        mdia_children.extend_from_slice(&minf);
                    }

                    let mdia = build_container_box(*b"mdia", &mdia_children);
                    trak_children.extend_from_slice(&mdia);
                }

                let trak = build_container_box(*b"trak", &trak_children);
                children.extend_from_slice(&trak);
            }

            // mvex > trex
            {
                let mut c = Vec::new();
                c.extend_from_slice(&1u32.to_be_bytes()); // track_ID
                c.extend_from_slice(&1u32.to_be_bytes()); // default_sample_description_index
                c.extend_from_slice(&0u32.to_be_bytes()); // default_sample_duration
                c.extend_from_slice(&0u32.to_be_bytes()); // default_sample_size
                c.extend_from_slice(&0u32.to_be_bytes()); // default_sample_flags
                let trex = build_full_box(*b"trex", 0, 0, &c);
                let mvex = build_container_box(*b"mvex", &trex);
                children.extend_from_slice(&mvex);
            }

            build_container_box(*b"moov", &children)
        };

        out.extend_from_slice(&moov);
        out
    }

    fn build_avcc(sps: &[u8], pps: &[u8]) -> Vec<u8> {
        // sps[0] is NAL header (0x67), sps[1] is profile_idc, sps[2] is profile_compat, sps[3] is level_idc
        let profile_idc = if sps.len() > 1 { sps[1] } else { 0 };
        let profile_compat = if sps.len() > 2 { sps[2] } else { 0u8 };
        let level_idc = if sps.len() > 3 { sps[3] } else { 0 };

        let mut c = vec![
            1, // configurationVersion
            profile_idc,
            profile_compat,
            level_idc,
            0xFF, // NALULengthSize = 4 (lengthSizeMinusOne = 3)
            0xE1, // numSPS = 1
        ];
        c.extend_from_slice(&(sps.len() as u16).to_be_bytes());
        c.extend_from_slice(sps);
        c.push(1); // numPPS
        c.extend_from_slice(&(pps.len() as u16).to_be_bytes());
        c.extend_from_slice(pps);

        build_container_box(*b"avcC", &c)
    }

    /// Build a media segment (moof + mdat) for one frame.
    pub fn write_media_segment(
        &mut self,
        nal_data: &[u8],
        timestamp_us: u64,
        is_keyframe: bool,
    ) -> Vec<u8> {
        self.sequence_number += 1;

        let avcc_data = annex_b_to_avcc(nal_data);
        let base_media_decode_time = timestamp_us * 90000 / 1_000_000;

        // Build moof
        let moof = {
            let mut moof_children = Vec::new();

            // mfhd
            {
                let mut c = Vec::new();
                c.extend_from_slice(&self.sequence_number.to_be_bytes());
                let mfhd = build_full_box(*b"mfhd", 0, 0, &c);
                moof_children.extend_from_slice(&mfhd);
            }

            // traf
            {
                let mut traf_children = Vec::new();

                // tfhd (flags=0x020000 default-base-is-moof)
                {
                    let mut c = Vec::new();
                    c.extend_from_slice(&1u32.to_be_bytes()); // track_ID
                    let tfhd = build_full_box(*b"tfhd", 0, 0x020000, &c);
                    traf_children.extend_from_slice(&tfhd);
                }

                // tfdt (version 1, 64-bit baseMediaDecodeTime)
                {
                    let mut c = Vec::new();
                    c.extend_from_slice(&base_media_decode_time.to_be_bytes());
                    let tfdt = build_full_box(*b"tfdt", 1, 0, &c);
                    traf_children.extend_from_slice(&tfdt);
                }

                // trun
                // flags: 0x000001 data-offset | 0x000100 sample-duration | 0x000200 sample-size
                //        | 0x000400 sample-flags (if first sample)
                {
                    let trun_flags: u32 = 0x000001 | 0x000100 | 0x000200 | 0x000400;
                    let mut c = Vec::new();
                    c.extend_from_slice(&1u32.to_be_bytes()); // sample_count
                    c.extend_from_slice(&0u32.to_be_bytes()); // data_offset placeholder (will patch)
                                                              // per-sample fields:
                    c.extend_from_slice(&3000u32.to_be_bytes()); // sample_duration
                    c.extend_from_slice(&(avcc_data.len() as u32).to_be_bytes()); // sample_size
                    let sample_flags: u32 = if is_keyframe { 0x02000000 } else { 0x01010000 };
                    c.extend_from_slice(&sample_flags.to_be_bytes());
                    let trun = build_full_box(*b"trun", 0, trun_flags, &c);
                    traf_children.extend_from_slice(&trun);
                }

                let traf = build_container_box(*b"traf", &traf_children);
                moof_children.extend_from_slice(&traf);
            }

            build_container_box(*b"moof", &moof_children)
        };

        // Now patch the data_offset in trun.
        // data_offset = moof_size + 8 (mdat header)
        let moof_size = moof.len() as u32;
        let data_offset = moof_size + 8;

        let mut moof = moof;
        // Find the trun data_offset field. The trun box contains:
        // [size(4)][type(4)][version(1)][flags(3)][sample_count(4)][data_offset(4)]
        // We need to find "trun" in the moof and patch the data_offset.
        if let Some(trun_pos) = moof.windows(4).position(|w| w == b"trun") {
            // trun_pos points to 't' in "trun"
            // After "trun": version(1) + flags(3) + sample_count(4) = 8 bytes
            // data_offset is at trun_pos + 4 + 8 = trun_pos + 12
            let offset_pos = trun_pos + 4 + 4 + 4; // type(already at +4 from size) + ver+flags(4) + sample_count(4)
            let bytes = data_offset.to_be_bytes();
            moof[offset_pos..offset_pos + 4].copy_from_slice(&bytes);
        }

        // Build mdat
        let mdat_size = (8 + avcc_data.len()) as u32;
        let mut result = Vec::with_capacity(moof.len() + 8 + avcc_data.len());
        result.extend_from_slice(&moof);
        result.extend_from_slice(&mdat_size.to_be_bytes());
        result.extend_from_slice(b"mdat");
        result.extend_from_slice(&avcc_data);

        result
    }
}

/// Read frames from a `StreamReceiver` and write them to an fMP4 file.
pub async fn write_mp4_file(
    mut receiver: crate::StreamReceiver,
    path: &std::path::Path,
) -> std::io::Result<()> {
    let mut file = tokio::fs::File::create(path).await?;
    let mut muxer = Mp4Muxer::new();
    let mut init_written = false;

    while let Some(frame) = receiver.next_frame().await {
        if frame.is_stream_end() {
            break;
        }

        if frame.is_codec_config() {
            // Parse SPS and PPS from the NAL units
            let nals = split_nals(&frame.data);
            let mut sps = None;
            let mut pps = None;
            for nal in &nals {
                if nal.is_empty() {
                    continue;
                }
                let nal_type = nal[0] & 0x1F;
                match nal_type {
                    7 => sps = Some(nal.to_vec()),
                    8 => pps = Some(nal.to_vec()),
                    _ => {}
                }
            }
            if let (Some(sps), Some(pps)) = (sps, pps) {
                let init = muxer.build_init_segment(&sps, &pps);
                file.write_all(&init).await?;
                muxer.set_sps_pps(sps, pps);
                init_written = true;
            }
            continue;
        }

        if !init_written {
            // Skip frames before SPS/PPS received
            continue;
        }

        let is_keyframe = frame.is_keyframe();
        let segment = muxer.write_media_segment(&frame.data, frame.timestamp_us, is_keyframe);
        file.write_all(&segment).await?;
    }

    file.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_annex_b_nals() {
        let data = vec![
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e, 0x00, 0x00, 0x00, 0x01, 0x68, 0xce,
            0x38, 0x80,
        ];
        let nals = split_nals(&data);
        assert_eq!(nals.len(), 2);
        assert_eq!(nals[0], &[0x67, 0x42, 0x00, 0x1e]);
        assert_eq!(nals[1], &[0x68, 0xce, 0x38, 0x80]);
    }

    #[test]
    fn annex_b_to_avcc_conversion() {
        let annex_b = vec![0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB];
        let avcc = annex_b_to_avcc(&annex_b);
        assert_eq!(avcc, vec![0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]);
    }

    #[test]
    fn init_segment_from_sps_pps() {
        let sps = vec![0x67, 0x42, 0x00, 0x1e, 0xab, 0x40, 0xa0, 0xfd];
        let pps = vec![0x68, 0xce, 0x38, 0x80];
        let muxer = Mp4Muxer::new();
        let init = muxer.build_init_segment(&sps, &pps);
        assert_eq!(&init[4..8], b"ftyp");
        let moov_pos = init.windows(4).position(|w| w == b"moov");
        assert!(moov_pos.is_some());
    }

    #[test]
    fn media_segment_structure() {
        let sps = vec![0x67, 0x42, 0x00, 0x1e, 0xab, 0x40, 0xa0, 0xfd];
        let pps = vec![0x68, 0xce, 0x38, 0x80];
        let mut muxer = Mp4Muxer::new();
        muxer.set_sps_pps(sps, pps);
        let nal_data = vec![0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB];
        let segment = muxer.write_media_segment(&nal_data, 0, true);
        let moof_pos = segment.windows(4).position(|w| w == b"moof");
        assert!(moof_pos.is_some());
        let mdat_pos = segment.windows(4).position(|w| w == b"mdat");
        assert!(mdat_pos.is_some());
    }
}
