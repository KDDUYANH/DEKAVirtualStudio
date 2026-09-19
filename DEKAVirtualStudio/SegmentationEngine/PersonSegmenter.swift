//
//  PersonSegmenter.swift
//  Two real back-ends behind one protocol:
//   • VisionPersonSegmenter — Apple's on-device person segmentation (Vision, runs on the ANE/GPU)
//   • CoreMLPersonSegmenter — any bundled Core ML matting model (e.g. a RobustVideoMatting export)
//     named "PersonSegmentation.mlmodelc". Not bundled by default; reported honestly as absent.
//

import Vision
import CoreML
import CoreVideo

protocol PersonSegmenter: AnyObject {
    var name: String { get }
    /// Returns a single-channel mask (0 = background, 1 = person), same framing as the input.
    func mask(for pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer
    func setQuality(_ q: SegmentationQuality)
}

enum SegmentationError: LocalizedError {
    case noResult, modelMissing
    var errorDescription: String? {
        switch self {
        case .noResult: return "Segmentation produced no mask."
        case .modelMissing: return "No Core ML segmentation model is bundled."
        }
    }
}

final class VisionPersonSegmenter: PersonSegmenter {
    let name = "Vision Person Segmentation"
    private let request = VNGeneratePersonSegmentationRequest()
    /// A sequence handler lets Vision use temporal information between frames (less flicker).
    private let sequence = VNSequenceRequestHandler()

    init(quality: SegmentationQuality) {
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        setQuality(quality)
    }

    func setQuality(_ q: SegmentationQuality) {
        switch q {
        case .fast: request.qualityLevel = .fast
        case .balanced: request.qualityLevel = .balanced
        case .accurate: request.qualityLevel = .accurate
        }
    }

    func mask(for pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        try sequence.perform([request], on: pixelBuffer, orientation: .up)
        guard let obs = request.results?.first else { throw SegmentationError.noResult }
        return obs.pixelBuffer
    }
}

final class CoreMLPersonSegmenter: PersonSegmenter {
    let name: String
    private let request: VNCoreMLRequest
    private let handler = VNSequenceRequestHandler()

    static var bundledModelURL: URL? {
        Bundle.main.url(forResource: "PersonSegmentation", withExtension: "mlmodelc")
    }

    init() throws {
        guard let url = Self.bundledModelURL else { throw SegmentationError.modelMissing }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: config)
        let vnModel = try VNCoreMLModel(for: model)
        request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill   // keep framing identical to the camera
        name = "Core ML (\(url.deletingPathExtension().lastPathComponent))"
    }

    func setQuality(_ q: SegmentationQuality) { /* fixed-resolution model */ }

    func mask(for pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        try handler.perform([request], on: pixelBuffer, orientation: .up)
        if let obs = request.results?.first as? VNPixelBufferObservation { return obs.pixelBuffer }
        throw SegmentationError.noResult
    }
}
