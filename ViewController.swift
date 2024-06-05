
import UIKit
import AVFoundation
import Foundation
import RosaKit

class ViewController: UIViewController {
    @IBOutlet weak var btnStart: UIButton!
    @IBOutlet weak var tvResult: UITextView!
    
    let audioEngine = AVAudioEngine()
    let serialQueue = DispatchQueue(label: "sasr.serial.queue")
    
    private let AUDIO_LEN_IN_SECOND = 2
    private let SAMPLE_RATE = 22050
    
    private let CHUNK_TO_READ = 5
    private let CHUNK_SIZE = 640
    private let INPUT_SIZE = 3200
    
    
    private var spectrograms = [[Double]]()
    
    private let module: InferenceModule = {
        if let filePath = Bundle.main.path(forResource:
            "streaming_asrv2", ofType: "ptl"),
            let module = InferenceModule(fileAtPath: filePath) {
            return module
        } else {
            fatalError("Can't find the model file!")
        }
    }()
    

    @IBAction func startTapped(_ sender: Any) {
        if (self.btnStart.title(for: .normal)! == "Start") {
            self.btnStart.setTitle("Listening... Stop", for: .normal)
            
            do {
              try self.startRecording()
            } catch let error {
              print("There was a problem starting recording: \(error.localizedDescription)")
            }
        }
        else {
            self.btnStart.setTitle("Start", for: .normal)
            self.stopRecording()
        }
    }
    
    private func loadData() {
        spectrograms = [[Double]]()
        
        let url = Bundle.main.url(forResource: "test", withExtension: "wav")
        
        let soundFile = url.flatMap { try? WavFileManager().readWavFile(at: $0) }
        
        let dataCount = soundFile?.data.count ?? 0
        let sampleRate = soundFile?.sampleRate ?? 44100
        let bytesPerSample = soundFile?.bytesPerSample ?? 0

        let chunkSize = 66000
        let chunksCount = dataCount/(chunkSize*bytesPerSample) - 1

        let rawData = soundFile?.data.int16Array
        
        for index in 0..<chunksCount-1 {
            let samples = Array(rawData?[chunkSize*index..<chunkSize*(index+1)] ?? []).map { Double($0)/32768.0 }
            let powerSpectrogram = samples.melspectrogram(nFFT: 1024, hopLength: 512, sampleRate: Int(sampleRate), melsCount: 128).map { $0.normalizeAudioPower() }
            spectrograms.append(contentsOf: powerSpectrogram.transposed)
        }
        
        print("Spectrogram:", spectrograms)

    }
}





//func generateMel() {
//    let rawAudioData = Data(...)
//
//    let chunkSize = 66000
//    let chunkOfSamples = Array(rawAudioData[0..<chunkSize])
//
//    let powerSpectrogram = samples.melspectrogram(nFFT: 1024, hopLength: 512, sampleRate: Int(sampleRate), melsCount: 128)
//}

extension ViewController {
    fileprivate func startRecording() throws {
        let inputNode = audioEngine.inputNode
        let inputNodeOutputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SAMPLE_RATE), channels: 1, interleaved: false)
        let formatConverter =  AVAudioConverter(from:inputNodeOutputFormat, to: targetFormat!)
        var pcmBufferToBeProcessed = [Float32]()
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNodeOutputFormat) { [unowned self] (buffer, _) in
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat!, frameCapacity: AVAudioFrameCount(targetFormat!.sampleRate) / 10)
                var error: NSError? = nil
            
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                formatConverter!.convert(to: pcmBuffer!, error: &error, withInputFrom: inputBlock)

                let floatArray = Array(UnsafeBufferPointer(start: pcmBuffer!.floatChannelData![0], count:Int(pcmBuffer!.frameLength)))
                pcmBufferToBeProcessed += floatArray
            
                if pcmBufferToBeProcessed.count >= CHUNK_TO_READ * CHUNK_SIZE {
                    let samples = Array(pcmBufferToBeProcessed[0..<CHUNK_TO_READ * CHUNK_SIZE])
                    pcmBufferToBeProcessed = Array(pcmBufferToBeProcessed[(CHUNK_TO_READ - 1) * CHUNK_SIZE..<pcmBufferToBeProcessed.count])
                    
                    print("FloatArray", floatArray)
                    print("Samples", samples)
                    
                    self.loadData()
                    
//                    serialQueue.async {
//                        var result = self.module.recognize(samples)
//                        if result!.count > 0 {
//                            result = result!.replacingOccurrences(of: "▁", with: "")
//                            DispatchQueue.main.async {
//                                print("Result", result!)
//                                self.tvResult.text = self.tvResult.text + " " + result!
//                            }
//                        }
//                    }
                }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    
    fileprivate func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
