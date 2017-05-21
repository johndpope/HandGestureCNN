//
//  ViewController.swift
//  HandGestureCNN
//
//  Created by 杨萧玉 on 2017/5/21.
//  Copyright © 2017年 杨萧玉. All rights reserved.
//

import UIKit
import MetalKit
import MetalPerformanceShaders
import Accelerate
import AVFoundation

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    // Outlets to label and view
    @IBOutlet private weak var predictLabel: UILabel!
    @IBOutlet private weak var previewView: UIView!
    
    // some properties used to control the app and store appropriate values
    private var Net: Inception3Net? = nil
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var textureLoader : MTKTextureLoader!
    private var ciContext : CIContext!
    private var sourceTexture : MTLTexture? = nil
    private var videoCapture: VideoCapture!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load default device.
        device = MTLCreateSystemDefaultDevice()
        
        // Make sure the current device supports MetalPerformanceShaders.
        guard MPSSupportsMTLDevice(device) else {
            print("Metal Performance Shaders not Supported on current Device")
            return
        }
        
        let spec = VideoSpec(fps: 3, size: CGSize(width: 1280, height: 720))
        videoCapture = VideoCapture(cameraType: .back,
                                    preferredSpec: spec,
                                    previewContainer: previewView.layer)
        videoCapture.imageBufferHandler = {[unowned self] (imageBuffer, timestamp, outputBuffer) in
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {return}
            
            // get a texture from this CGImage
            do {
                self.sourceTexture = try self.textureLoader.newTexture(with: cgImage, options: [:])
            }
            catch let error as NSError {
                fatalError("Unexpected error ocurred: \(error.localizedDescription).")
            }
            // run inference neural network to get predictions and display them
            self.runNetwork()
        }
        
        // Load any resources required for rendering.
        
        // Create new command queue.
        commandQueue = device.makeCommandQueue()
        
        // make a textureLoader to get our input images as MTLTextures
        textureLoader = MTKTextureLoader(device: device)
        
        // Load the appropriate Network
        Net = Inception3Net(withCommandQueue: commandQueue)
        
        // we use this CIContext as one of the steps to get a MTLTexture
        ciContext = CIContext.init(mtlDevice: device)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let videoCapture = videoCapture else {return}
        videoCapture.startCapture()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let videoCapture = videoCapture else {return}
        videoCapture.resizePreview()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        guard let videoCapture = videoCapture else {return}
        videoCapture.stopCapture()
        
        navigationController?.setNavigationBarHidden(false, animated: true)
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    /**
     This function gets a commanBuffer and encodes layers in it. It follows that by commiting the commandBuffer and getting labels
     */
    func runNetwork() {
        let startTime = CACurrentMediaTime()
        
        // to deliver optimal performance we leave some resources used in MPSCNN to be released at next call of autoreleasepool,
        // so the user can decide the appropriate time to release this
        autoreleasepool{
            // encoding command buffer
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            // encode all layers of network on present commandBuffer, pass in the input image MTLTexture
            Net?.forward(commandBuffer: commandBuffer, sourceTexture: sourceTexture)
            
            // commit the commandBuffer and wait for completion on CPU
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // display top-5 predictions for what the object should be labelled
            var resultStr = ""
            Net?.getResults().forEach({ (label, prob) in
                resultStr = resultStr + label + "\t" + String(format: "%.1f", prob * 100) + "%\n\n"
            })
            
            DispatchQueue.main.async {
                self.predictLabel.text = resultStr
            }
        }
        
        let endTime = CACurrentMediaTime()
        print("Running Time: \(endTime - startTime) [sec]")
    }
}


