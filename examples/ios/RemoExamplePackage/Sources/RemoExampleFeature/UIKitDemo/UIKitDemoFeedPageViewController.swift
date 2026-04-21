#if canImport(UIKit)
import UIKit

final class UIKitDemoFeedPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<FeedCardCell, UIKitDemoCard> {
        cell, _, card in
        cell.configure(with: card)
    }

    private(set) lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: buildLayout(for: []))
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.showsVerticalScrollIndicator = false
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, UIKitDemoCard>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, card in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: card)
    }

    private var cards: [UIKitDemoCard] = []
    var onVerticalOffsetChange: ((CGFloat) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.delegate = self
    }

    func apply(cards: [UIKitDemoCard], restoringOffset: CGFloat) {
        self.cards = cards
        collectionView.setCollectionViewLayout(buildLayout(for: cards), animated: false)
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIKitDemoCard>()
        snapshot.appendSections([.main])
        snapshot.appendItems(cards)
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleCards() -> [UIKitDemoCard] {
        collectionView.indexPathsForVisibleItems
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }
    }

    @discardableResult
    func scroll(to position: UIKitDemoScrollPosition, animated: Bool) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - inset.top - inset.bottom
        let contentHeight = collectionView.contentSize.height
        let maxOffset = max(-inset.top, contentHeight - visibleHeight)

        let y: CGFloat
        switch position {
        case .top: y = -inset.top
        case .middle: y = max(-inset.top, maxOffset / 2)
        case .bottom: y = maxOffset
        }
        collectionView.setContentOffset(.init(x: 0, y: y), animated: animated)
        return y
    }

    private func buildLayout(for cards: [UIKitDemoCard]) -> UICollectionViewCompositionalLayout {
        let horizontalMargin: CGFloat = 8
        let gutter: CGFloat = 12
        let topInset: CGFloat = 8
        let bottomInset: CGFloat = 24

        return UICollectionViewCompositionalLayout { _, environment in
            let available = environment.container.effectiveContentSize.width - horizontalMargin * 2
            let columnWidth = max(1, (available - gutter) / 2)

            var leftY: CGFloat = 0
            var rightY: CGFloat = 0
            var frames: [CGRect] = []
            frames.reserveCapacity(cards.count)

            for card in cards {
                let height = FeedLayoutMath.cellHeight(for: card, width: columnWidth)
                if card.column == 0 {
                    let frame = CGRect(
                        x: horizontalMargin,
                        y: leftY,
                        width: columnWidth,
                        height: height
                    )
                    frames.append(frame)
                    leftY += height + gutter
                } else {
                    let frame = CGRect(
                        x: horizontalMargin + columnWidth + gutter,
                        y: rightY,
                        width: columnWidth,
                        height: height
                    )
                    frames.append(frame)
                    rightY += height + gutter
                }
            }

            let totalHeight = max(0, max(leftY, rightY) - gutter)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(totalHeight)
            )
            let group = NSCollectionLayoutGroup.custom(layoutSize: groupSize) { _ in
                frames.map { NSCollectionLayoutGroupCustomItem(frame: $0) }
            }
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: topInset,
                leading: 0,
                bottom: bottomInset,
                trailing: 0
            )
            return section
        }
    }
}

extension UIKitDemoFeedPageViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onVerticalOffsetChange?(scrollView.contentOffset.y)
    }
}

private enum FeedLayoutMath {
    static let cardHorizontalPadding: CGFloat = 8
    static let footerSpacing: CGFloat = 6
    static let footerVerticalPadding: CGFloat = 8
    static let metaRowHeight: CGFloat = 14
    static let captionFont = UIFont.systemFont(ofSize: 13, weight: .regular)
    static let maxCaptionLines: Int = 2

    static func mediaHeight(for card: UIKitDemoCard, width: CGFloat) -> CGFloat {
        guard card.aspectWidth > 0 else { return width }
        let ratio = CGFloat(card.aspectHeight) / CGFloat(card.aspectWidth)
        return (width * ratio).rounded()
    }

    static func cellHeight(for card: UIKitDemoCard, width: CGFloat) -> CGFloat {
        let media = mediaHeight(for: card, width: width)
        let footer = card.showsFooter ? footerHeight(for: card, width: width) : 0
        return media + footer
    }

    static func footerHeight(for card: UIKitDemoCard, width: CGFloat) -> CGFloat {
        let contentWidth = max(1, width - cardHorizontalPadding * 2)
        let caption = card.title.isEmpty ? 0 : captionHeight(text: card.title, width: contentWidth)
        let showsMeta = card.author != nil || card.likes != nil
        let meta = showsMeta ? metaRowHeight : 0
        let between = caption > 0 && meta > 0 ? footerSpacing : 0
        return footerVerticalPadding + caption + between + meta + footerVerticalPadding
    }

    private static func captionHeight(text: String, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: captionFont],
            context: nil
        )
        let cap = ceil(captionFont.lineHeight * CGFloat(maxCaptionLines))
        return min(ceil(bounding.height), cap)
    }
}

private final class FeedCardCell: UICollectionViewCell {
    private let mediaView = UIView()
    private let playIcon = UIImageView()
    private let captionLabel = UILabel()
    private let authorAvatar = UIView()
    private let authorLabel = UILabel()
    private let likeIcon = UIImageView()
    private let likeLabel = UILabel()
    private let footerStack = UIStackView()
    private let metaRow = UIStackView()
    private var mediaAspectConstraint: NSLayoutConstraint?
    private var mediaBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        mediaView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mediaView)

        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.image = UIImage(systemName: "play.circle.fill")?.withRenderingMode(.alwaysTemplate)
        playIcon.tintColor = UIColor.white.withAlphaComponent(0.95)
        contentView.addSubview(playIcon)

        captionLabel.font = FeedLayoutMath.captionFont
        captionLabel.textColor = .black
        captionLabel.numberOfLines = FeedLayoutMath.maxCaptionLines
        captionLabel.lineBreakMode = .byTruncatingTail

        authorAvatar.translatesAutoresizingMaskIntoConstraints = false
        authorAvatar.layer.cornerRadius = 7
        authorAvatar.layer.masksToBounds = true

        authorLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        authorLabel.textColor = UIColor.black.withAlphaComponent(0.48)
        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        likeIcon.image = UIImage(systemName: "heart")?.withRenderingMode(.alwaysTemplate)
        likeIcon.tintColor = UIColor.black.withAlphaComponent(0.48)
        likeIcon.translatesAutoresizingMaskIntoConstraints = false

        likeLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        likeLabel.textColor = UIColor.black.withAlphaComponent(0.48)
        likeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let authorRow = UIStackView(arrangedSubviews: [authorAvatar, authorLabel])
        authorRow.axis = .horizontal
        authorRow.alignment = .center
        authorRow.spacing = 4

        let likeRow = UIStackView(arrangedSubviews: [likeIcon, likeLabel])
        likeRow.axis = .horizontal
        likeRow.alignment = .center
        likeRow.spacing = 3

        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 4
        metaRow.addArrangedSubview(authorRow)
        metaRow.addArrangedSubview(likeRow)

        footerStack.axis = .vertical
        footerStack.spacing = FeedLayoutMath.footerSpacing
        footerStack.alignment = .fill
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.addArrangedSubview(captionLabel)
        footerStack.addArrangedSubview(metaRow)
        contentView.addSubview(footerStack)

        NSLayoutConstraint.activate([
            mediaView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mediaView.topAnchor.constraint(equalTo: contentView.topAnchor),

            playIcon.widthAnchor.constraint(equalToConstant: 16),
            playIcon.heightAnchor.constraint(equalToConstant: 16),
            playIcon.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 8),
            playIcon.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -8),

            authorAvatar.widthAnchor.constraint(equalToConstant: 14),
            authorAvatar.heightAnchor.constraint(equalToConstant: 14),
            likeIcon.widthAnchor.constraint(equalToConstant: 12),
            likeIcon.heightAnchor.constraint(equalToConstant: 12),

            footerStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: FeedLayoutMath.cardHorizontalPadding
            ),
            footerStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -FeedLayoutMath.cardHorizontalPadding
            ),
            footerStack.topAnchor.constraint(
                equalTo: mediaView.bottomAnchor,
                constant: FeedLayoutMath.footerVerticalPadding
            ),
            footerStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -FeedLayoutMath.footerVerticalPadding
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with card: UIKitDemoCard) {
        let hue = CGFloat(card.tintHue)
        mediaView.backgroundColor = UIColor(hue: hue, saturation: 0.35, brightness: 0.9, alpha: 1)
        playIcon.isHidden = !card.hasPlayIcon

        let aspect = max(CGFloat(card.aspectHeight) / max(CGFloat(card.aspectWidth), 1), 0.1)
        if let existing = mediaAspectConstraint {
            existing.isActive = false
        }
        let aspectConstraint = mediaView.heightAnchor.constraint(
            equalTo: mediaView.widthAnchor,
            multiplier: aspect
        )
        aspectConstraint.priority = .required - 1
        aspectConstraint.isActive = true
        mediaAspectConstraint = aspectConstraint

        if let existing = mediaBottomConstraint {
            existing.isActive = false
        }
        if card.showsFooter {
            footerStack.isHidden = false
            captionLabel.text = card.title.isEmpty ? " " : card.title
            captionLabel.isHidden = card.title.isEmpty
            let showsMeta = card.author != nil || card.likes != nil
            metaRow.isHidden = !showsMeta
            authorAvatar.backgroundColor = UIColor(
                hue: hue + 0.1,
                saturation: 0.5,
                brightness: 0.7,
                alpha: 1
            )
            authorLabel.text = card.author
            likeIcon.isHidden = card.likes == nil
            likeLabel.text = card.likes
            mediaBottomConstraint = nil
        } else {
            footerStack.isHidden = true
            let bottom = mediaView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            bottom.isActive = true
            mediaBottomConstraint = bottom
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        captionLabel.text = nil
        authorLabel.text = nil
        likeLabel.text = nil
    }
}
#endif
