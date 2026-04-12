#if canImport(UIKit)
import UIKit
import RemoSwift

final class SpikeStmtViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #Remo {
            enum Navigate: RemoCapability {
                static let name = "navigate"

                struct Request: Decodable {
                    let route: String?
                }

                typealias Response = RemoOK
            }

            #remoScope(scopedTo: self) {
                #remoCap(Navigate.self) { req in
                    _ = req.route
                    return RemoOK()
                }
            }
        }
    }
}
#endif
