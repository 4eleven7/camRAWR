//
//  VideoSessionController.swift
//  camRAWR
//
//  Created by Daniel Love on 05/10/2015.
//  Copyright © 2015 Shh Love Limited. All rights reserved.
//

import AVFoundation

enum VideoSessionPermission
{
	case Requestable
	case RestrictedByParent
	case Denied
	case Granted
}

class VideoSessionController : NSObject
{
	let session : AVCaptureSession
	let previewLayer : AVCaptureVideoPreviewLayer
	
	var backCameraDevice : AVCaptureDevice?
	var frontCameraDevice : AVCaptureDevice?
	var currentCameraDevice : AVCaptureDevice?
	
	var metadataOutput : AVCaptureMetadataOutput
	
	var didDetectFacesHandler:((Array<(faceID: Int, frame : CGRect)>)->Void)!
	
	let sessionQueue : dispatch_queue_t = dispatch_queue_create("net.daniellove.camRAWR.session_access_queue", DISPATCH_QUEUE_SERIAL)
	
	override init()
	{
		session = AVCaptureSession()
		session.sessionPreset = AVCaptureSessionPresetPhoto
		
		previewLayer = AVCaptureVideoPreviewLayer(session: self.session) as AVCaptureVideoPreviewLayer
		previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
		
		metadataOutput = AVCaptureMetadataOutput()
	}
	
// MARK: Authorization
	
	func checkAuthorizationStatus() -> VideoSessionPermission
	{
		let authorizationStatus = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
		
		var permission : VideoSessionPermission
		
		switch authorizationStatus
		{
			case .Authorized:
				permission = VideoSessionPermission.Granted
			case .NotDetermined:
				permission = VideoSessionPermission.Requestable
			case .Denied:
				permission = VideoSessionPermission.Denied
			case .Restricted:
				permission = VideoSessionPermission.RestrictedByParent
		}
		
		return permission
	}
	
	func requestAuthorization(completionHandler: ((granted : Bool) -> Void))
	{
		AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: completionHandler)
	}
	
// MARK: Controls
	
	func startSession()
	{
		performConfiguration { () -> Void in
			self.session.startRunning()
		}
	}
	
	func stopSession()
	{
		performConfiguration { () -> Void in
			self.session.stopRunning()
		}
	}
	
// MARK: Device Configuration
	
	func configureSession()
	{
		findCameraDevices()
		setupDeviceInput()
		enableContinuousAutoFocus()
		configureFaceDetection()
	}
	
	func performConfiguration(block: (() -> Void))
	{
		dispatch_async(sessionQueue) { () -> Void in
			block()
		}
	}
	
	func performConfigurationOnCurrentCameraDevice(block: ((currentDevice:AVCaptureDevice) -> Void))
	{
		if let currentDevice = self.currentCameraDevice
		{
			performConfiguration { () -> Void in
				do
				{
					try currentDevice.lockForConfiguration()
					block(currentDevice: currentDevice)
					currentDevice.unlockForConfiguration()
				}
				catch let error
				{
					NSLog("\(error)")
				}
			}
		}
	}
	
	func findCameraDevices()
	{
		performConfiguration { () -> Void in
			let availableCameraDevices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
			
			for device in availableCameraDevices as! [AVCaptureDevice]
			{
				if device.position == .Back {
					self.backCameraDevice = device
				}
				else if device.position == .Front {
					self.frontCameraDevice = device
				}
			}
		}
	}
	
	func setupDeviceInput()
	{
		performConfiguration { () -> Void in
			// Prefer the front camera
			if (self.frontCameraDevice != nil) {
				self.currentCameraDevice = self.frontCameraDevice
			} else {
				self.currentCameraDevice = self.backCameraDevice
			}
			
			let possibleCameraInput: AnyObject?
			do
			{
				possibleCameraInput = try AVCaptureDeviceInput(device: self.currentCameraDevice)
			}
			catch let error
			{
				NSLog("\(error)")
				possibleCameraInput = nil
			}
			
			if let cameraInput = possibleCameraInput as? AVCaptureDeviceInput
			{
				if self.session.canAddInput(cameraInput) {
					self.session.addInput(cameraInput)
				}
			}
		}
	}
	
// MARK: Face Detection
	
	func configureFaceDetection()
	{
		performConfiguration { () -> Void in
			self.metadataOutput = AVCaptureMetadataOutput()
			self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
			
			if self.session.canAddOutput(self.metadataOutput) {
				self.session.addOutput(self.metadataOutput)
			}
			
			if let availableMetadataObjectTypes = self.metadataOutput.availableMetadataObjectTypes as? [String]
			{
				if availableMetadataObjectTypes.contains(AVMetadataObjectTypeFace) {
					self.metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
				}
			}
		}
	}
	
// MARK: Focus
	
	var isAutoFocusContinuousEnabled : Bool {
		get {
			return currentCameraDevice!.focusMode == .ContinuousAutoFocus
		}
	}
	
	func enableContinuousAutoFocus()
	{
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.isFocusModeSupported(.ContinuousAutoFocus) {
				currentDevice.focusMode = .ContinuousAutoFocus
			}
		}
	}
	
	var isAutoFocusLockedEnabled : Bool {
		get {
			return currentCameraDevice!.focusMode == .Locked
		}
	}
	
	func lockFocusAtPointOfInterest(pointInView : CGPoint)
	{
		let pointInCamera = previewLayer.captureDevicePointOfInterestForPoint(pointInView)
		performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
			if currentDevice.focusPointOfInterestSupported {
				currentDevice.focusPointOfInterest = pointInCamera
				currentDevice.focusMode = .AutoFocus
			}
		}
	}
}

extension VideoSessionController: AVCaptureMetadataOutputObjectsDelegate
{
	func captureOutput(captureOutput : AVCaptureOutput!, didOutputMetadataObjects metadataObjects : [AnyObject]!, fromConnection connection : AVCaptureConnection!)
	{
		var faces = Array<(faceID: Int, frame : CGRect)>()
		
		for metadataObject in metadataObjects as! [AVMetadataObject]
		{
			if metadataObject.type != AVMetadataObjectTypeFace {
				continue
			}
			
			if let faceObject = metadataObject as? AVMetadataFaceObject
			{
				let transformedMetadataObject = previewLayer.transformedMetadataObjectForMetadataObject(metadataObject)
				let face = (faceObject.faceID, transformedMetadataObject.bounds)
				faces.append(face)
			}
		}
		
		if let handler = self.didDetectFacesHandler
		{
			dispatch_async(dispatch_get_main_queue(), {
				handler(faces)
			})
		}
	}
}
