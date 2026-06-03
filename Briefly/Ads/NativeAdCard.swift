import GoogleMobileAds
import SwiftUI
import UIKit

struct NativeAdCard: View {
    let slot: NativeAdSlot
    @StateObject private var viewModel: NativeAdViewModel

    init(slot: NativeAdSlot) {
        self.slot = slot
        _viewModel = StateObject(
            wrappedValue: NativeAdViewModel(
                adUnitID: AppConfig.shared.nativeAdUnitID(for: slot.placement)
            )
        )
    }

    var body: some View {
        Group {
            if let nativeAd = viewModel.nativeAd {
                NativeAdViewContainer(nativeAd: nativeAd)
                    .frame(height: 178)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let loadError = viewModel.loadError {
                #if DEBUG
                NativeAdDebugPlaceholder(message: loadError)
                    .frame(height: 78)
                #else
                Color.clear.frame(height: 1)
                #endif
            } else {
                #if DEBUG
                NativeAdDebugPlaceholder(message: "Requesting native ad...")
                    .frame(height: 78)
                #else
                Color.clear.frame(height: 1)
                #endif
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
    }
}

@MainActor
final class NativeAdViewModel: NSObject, ObservableObject {
    @Published var nativeAd: NativeAd?
    @Published var loadError: String?

    private let adUnitID: String
    private var adLoader: AdLoader?
    private var didRequestAd = false

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
    }

    func loadIfNeeded() {
        guard !didRequestAd else { return }
        guard !adUnitID.isEmpty else {
            loadError = "Missing native ad unit ID"
            #if DEBUG
            print("[AdMob] Native ad skipped: missing ad unit ID")
            #endif
            return
        }

        didRequestAd = true
        #if DEBUG
        print("[AdMob] Loading native ad unit: \(adUnitID)")
        #endif
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: UIApplication.shared.brieflyTopViewController,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }
}

extension NativeAdViewModel: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in
            nativeAd.delegate = self
            loadError = nil
            self.nativeAd = nativeAd
            #if DEBUG
            print("[AdMob] Native ad loaded: \(self.adUnitID)")
            #endif
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in
            nativeAd = nil
            let nsError = error as NSError
            loadError = "Ad load failed: \(nsError.domain) \(nsError.code)"
            #if DEBUG
            print("[AdMob] Native ad failed: unit=\(self.adUnitID) domain=\(nsError.domain) code=\(nsError.code) info=\(nsError.userInfo)")
            #endif
        }
    }
}

extension NativeAdViewModel: NativeAdDelegate {}

private struct NativeAdDebugPlaceholder: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.badge.xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("AdMob diagnostic")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct NativeAdViewContainer: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> BrieflyNativeAdView {
        BrieflyNativeAdView()
    }

    func updateUIView(_ uiView: BrieflyNativeAdView, context: Context) {
        uiView.configure(with: nativeAd)
    }
}

private final class BrieflyNativeAdView: NativeAdView {
    private let containerView = UIView()
    private let labelContainer = UIView()
    private let sponsoredLabel = UILabel()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let advertiserLabel = UILabel()
    private let callToActionLabel = UILabel()
    private let iconImageView = UIImageView()
    private let adMediaView = MediaView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(with ad: NativeAd) {
        nativeAd = nil

        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = ad.body == nil
        advertiserLabel.text = ad.advertiser ?? "Sponsored"
        callToActionLabel.text = ad.callToAction ?? "Learn More"
        iconImageView.image = ad.icon?.image
        iconImageView.isHidden = ad.icon == nil
        adMediaView.mediaContent = ad.mediaContent

        nativeAd = ad
    }

    private func setup() {
        backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.brieflyElevatedCard
        containerView.layer.cornerRadius = 18
        containerView.layer.cornerCurve = .continuous
        containerView.layer.borderColor = UIColor.brieflyBorder.cgColor
        containerView.layer.borderWidth = 1
        containerView.clipsToBounds = true
        addSubview(containerView)

        adMediaView.translatesAutoresizingMaskIntoConstraints = false
        adMediaView.backgroundColor = UIColor.brieflyCard
        adMediaView.contentMode = .scaleAspectFill
        containerView.addSubview(adMediaView)

        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(labelContainer)

        sponsoredLabel.translatesAutoresizingMaskIntoConstraints = false
        sponsoredLabel.text = "Sponsored"
        sponsoredLabel.font = .systemFont(ofSize: 10, weight: .bold)
        sponsoredLabel.textColor = UIColor.brieflyAccent
        sponsoredLabel.setContentHuggingPriority(.required, for: .horizontal)
        labelContainer.addSubview(sponsoredLabel)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.layer.cornerRadius = 8
        iconImageView.clipsToBounds = true
        labelContainer.addSubview(iconImageView)

        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        headlineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        headlineLabel.textColor = UIColor.brieflyPrimaryText
        headlineLabel.numberOfLines = 2
        labelContainer.addSubview(headlineLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bodyLabel.textColor = UIColor.brieflySecondaryText
        bodyLabel.numberOfLines = 2
        labelContainer.addSubview(bodyLabel)

        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        advertiserLabel.font = .systemFont(ofSize: 11, weight: .medium)
        advertiserLabel.textColor = UIColor.brieflySecondaryText
        advertiserLabel.numberOfLines = 1
        labelContainer.addSubview(advertiserLabel)

        callToActionLabel.translatesAutoresizingMaskIntoConstraints = false
        callToActionLabel.font = .systemFont(ofSize: 12, weight: .bold)
        callToActionLabel.textColor = .white
        callToActionLabel.textAlignment = .center
        callToActionLabel.backgroundColor = UIColor.brieflyAccent
        callToActionLabel.layer.cornerRadius = 12
        callToActionLabel.layer.cornerCurve = .continuous
        callToActionLabel.clipsToBounds = true
        callToActionLabel.isUserInteractionEnabled = false
        labelContainer.addSubview(callToActionLabel)

        mediaView = adMediaView
        headlineView = headlineLabel
        bodyView = bodyLabel
        iconView = iconImageView
        advertiserView = advertiserLabel
        callToActionView = callToActionLabel

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            adMediaView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            adMediaView.topAnchor.constraint(equalTo: containerView.topAnchor),
            adMediaView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            adMediaView.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.36),

            labelContainer.leadingAnchor.constraint(equalTo: adMediaView.trailingAnchor, constant: 14),
            labelContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            labelContainer.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            labelContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14),

            sponsoredLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
            sponsoredLabel.topAnchor.constraint(equalTo: labelContainer.topAnchor),

            iconImageView.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor),
            iconImageView.topAnchor.constraint(equalTo: labelContainer.topAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            headlineLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: iconImageView.leadingAnchor, constant: -10),
            headlineLabel.topAnchor.constraint(equalTo: sponsoredLabel.bottomAnchor, constant: 8),

            bodyLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 6),

            advertiserLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
            advertiserLabel.trailingAnchor.constraint(lessThanOrEqualTo: callToActionLabel.leadingAnchor, constant: -10),
            advertiserLabel.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor, constant: -2),

            callToActionLabel.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor),
            callToActionLabel.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor),
            callToActionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            callToActionLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
}

private extension UIApplication {
    var brieflyTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .brieflyTopMostViewController
    }
}

private extension UIViewController {
    var brieflyTopMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.brieflyTopMostViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.brieflyTopMostViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.brieflyTopMostViewController
        }

        return self
    }
}

private extension UIColor {
    static let brieflyCard = UIColor(red: CGFloat(0x11) / 255, green: CGFloat(0x11) / 255, blue: CGFloat(0x18) / 255, alpha: 1)
    static let brieflyElevatedCard = UIColor(red: CGFloat(0x18) / 255, green: CGFloat(0x18) / 255, blue: CGFloat(0x24) / 255, alpha: 1)
    static let brieflyPrimaryText = UIColor(red: CGFloat(0xF7) / 255, green: CGFloat(0xF4) / 255, blue: CGFloat(0xFF) / 255, alpha: 1)
    static let brieflySecondaryText = UIColor(red: CGFloat(0xA7) / 255, green: CGFloat(0xA1) / 255, blue: CGFloat(0xB8) / 255, alpha: 1)
    static let brieflyAccent = UIColor(red: CGFloat(0x7B) / 255, green: CGFloat(0x3C) / 255, blue: CGFloat(0xFF) / 255, alpha: 1)
    static let brieflyBorder = UIColor(red: CGFloat(0x25) / 255, green: CGFloat(0x25) / 255, blue: CGFloat(0x38) / 255, alpha: 1)
}
