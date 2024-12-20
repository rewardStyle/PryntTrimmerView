//
//  ThumbSelectorView.swift
//  Pods
//
//  Created by Henry on 06/04/2017.
//
//

import UIKit
import AVFoundation

/// A delegate to be notified of when the thumb position has changed. Useful to link an instance of the ThumbSelectorView to a
/// video preview like an `AVPlayer`.
public protocol ThumbSelectorViewDelegate: AnyObject {
    func didChangeThumbPosition(_ imageTime: CMTime)
}

/// A view to select a specific time of an `AVAsset`. It is composed of an asset preview within a scroll view, and a thumb view
/// to select a precise time of the video. Set the `asset` property to load the video, and use the `selectedTime` property to
// retrieve the exact frame of the asset that was selected.
public class ThumbSelectorView: AVAssetTimeSelector {

    public var thumbBorderColor: UIColor = .white {
        didSet {
            thumbView.layer.borderColor = thumbBorderColor.cgColor
        }
    }

    private let thumbView = UIImageView()
    private let dimmingView = UIView()

    private var leftThumbConstraint: NSLayoutConstraint?
    private var currentThumbConstraint: CGFloat = 0

    private var generator: AVAssetImageGenerator?

    public weak var delegate: ThumbSelectorViewDelegate?

    private(set) var thumbViewWidthConstraint: NSLayoutConstraint?

    // MARK: - View & constraints configurations

    override func setupSubviews() {
        super.setupSubviews()
        setupDimmingView()
        setupThumbView()
        thumbSelectorTrackTappedHandler = { [weak self] location in
            guard let self = self else  { return }
            self.disableGestureRecognizers()
            self.resetThumbViewBorderColor()
            let width = self.thumbView.frame.size.width / 2
            self.leftThumbConstraint?.constant = location.x - width
            self.layoutIfNeeded()
            self.updateSelectedTime()
        }
    }
    /// Clears the thumb view image and sets the thumb border color to clear. This also has a side effect of enabling
    /// gesture recognizers that will listen for taps on the cover selector to enable cover selection again if a user taps
    /// anywhere in the view.
    public func clearThumbSelectorViewStartingFrame() {
        enableGestureRecognizers()
        thumbView.image = nil
        thumbBorderColor = .clear
    }

    public func resetThumbViewBorderColor(to color: UIColor = .white) {
        thumbBorderColor = color
    }

    public func applyCustomThumbSelectorDimmingViewColor(_ color: UIColor) {
        dimmingView.backgroundColor = color
    }

    private func setupDimmingView() {

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.isUserInteractionEnabled = false
        dimmingView.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        addSubview(dimmingView)
        dimmingView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        dimmingView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        dimmingView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    private func setupThumbView() {

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.layer.borderWidth = 2.0
        thumbView.layer.cornerRadius = 4.0
        thumbView.layer.borderColor = thumbBorderColor.cgColor
        thumbView.isUserInteractionEnabled = true
        thumbView.contentMode = .scaleAspectFill
        thumbView.clipsToBounds = true
        addSubview(thumbView)

        leftThumbConstraint = thumbView.leftAnchor.constraint(equalTo: leftAnchor)
        leftThumbConstraint?.isActive = true
        thumbViewWidthConstraint = thumbView.widthAnchor.constraint(equalTo: thumbView.heightAnchor)
        thumbViewWidthConstraint?.isActive = true
        thumbView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
        thumbView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        assetPreview.assetVideoDelegate = self
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(ThumbSelectorView.handlePanGesture(_:)))
        thumbView.addGestureRecognizer(panGestureRecognizer)
    }

    // MARK: - Gesture handling

    @objc func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let superView = gestureRecognizer.view?.superview else { return }

        switch gestureRecognizer.state {

        case .began:
            currentThumbConstraint = leftThumbConstraint!.constant
            updateSelectedTime()
        case .changed:

            let translation = gestureRecognizer.translation(in: superView)
            updateThumbConstraint(with: translation)
            layoutIfNeeded()
            updateSelectedTime()

        case .cancelled, .ended, .failed:
            updateSelectedTime()
        default: break
        }
    }

    private func updateThumbConstraint(with translation: CGPoint) {
        let maxConstraint = frame.width - thumbView.frame.width
        let newConstraint = min(max(0, currentThumbConstraint + translation.x), maxConstraint)
        leftThumbConstraint?.constant = newConstraint
    }

    // MARK: - Thumbnail Generation

    override func assetDidChange(newAsset: AVAsset?) {
        if let asset = newAsset {
            setupThumbnailGenerator(with: asset)
            leftThumbConstraint?.constant = 0
            updateSelectedTime()
        }
        super.assetDidChange(newAsset: newAsset)
    }

    private func setupThumbnailGenerator(with asset: AVAsset) {
        generator = AVAssetImageGenerator(asset: asset)
        generator?.appliesPreferredTrackTransform = true
        generator?.requestedTimeToleranceAfter = CMTime.zero
        generator?.requestedTimeToleranceBefore = CMTime.zero
        generator?.maximumSize = getThumbnailFrameSize(from: asset) ?? CGSize.zero
    }

    private func getThumbnailFrameSize(from asset: AVAsset) -> CGSize? {
        guard let track = asset.tracks(withMediaType: AVMediaType.video).first else { return nil}

        let assetSize = track.naturalSize.applying(track.preferredTransform)

        let maxDimension = max(assetSize.width, assetSize.height)
        let minDimension = min(assetSize.width, assetSize.height)
        let ratio = maxDimension / minDimension
        let side = thumbView.frame.height * ratio * UIScreen.main.scale
        return CGSize(width: side, height: side)
    }

    private func generateThumbnailImage(for time: CMTime) {

        generator?.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)],
                                                  completionHandler: { (_, image, _, _, _) in
            guard let image = image else {
                return
            }
            DispatchQueue.main.async {
                self.generator?.cancelAllCGImageGeneration()
                let uiimage = UIImage(cgImage: image)
                self.thumbView.image = uiimage
            }
        })
    }

    // MARK: - Time & Position Equivalence

    override var durationSize: CGFloat {
        return assetPreview.contentSize.width - thumbView.frame.width
    }

    /// The currently selected time of the asset.
    public var selectedTime: CMTime? {
        let thumbPosition = thumbView.center.x + assetPreview.contentOffset.x - (thumbView.frame.width / 2)
        return getTime(from: thumbPosition)
    }

    private func updateSelectedTime() {
        if let selectedTime = selectedTime {
            delegate?.didChangeThumbPosition(selectedTime)
            generateThumbnailImage(for: selectedTime)
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateSelectedTime()
    }
}

// MARK: - AssetVideoScrollViewDelegate Conformance

extension ThumbSelectorView: AssetVideoScrollViewDelegate {

    func didUpdateThumbnails(to size: CGSize, for asset: AVAsset) {
        thumbViewWidthConstraint?.isActive = false
        if size.width < size.height {
            thumbViewWidthConstraint = thumbView.widthAnchor.constraint(equalToConstant: size.width)
        } else {
            thumbViewWidthConstraint = thumbView.widthAnchor.constraint(equalTo: thumbView.heightAnchor)
        }
        thumbViewWidthConstraint?.isActive = true
    }
}
