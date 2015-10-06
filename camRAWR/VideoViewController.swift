//
//  VideoViewController.swift
//  camRAWR
//
//  Created by Daniel Love on 05/10/2015.
//  Copyright © 2015 Shh Love Limited. All rights reserved.
//

import UIKit
import AVFoundation

class VideoViewController : UIViewController
{
	@IBOutlet var previewView : UIView!
	@IBOutlet var facesView : UIView!
	private var faceViews = [UIView]()
	
	lazy var sessionController : VideoSessionController = {
		return VideoSessionController();
	}();
	
	override func viewDidLoad()
	{
		super.viewDidLoad()
		
		checkAuthorizationAndStartPreview()
	}
	
	override func didReceiveMemoryWarning()
	{
		super.didReceiveMemoryWarning()
	}
	
	func checkAuthorizationAndStartPreview()
	{
		let authorizationStatus = sessionController.checkAuthorizationStatus()
		
		switch authorizationStatus
		{
			case .Granted:
				showCameraPreview()
			
			case .Denied:
				showAccessDeniedMessage()
			
			case .RestrictedByParent:
				showAccessRestrictedMessage()
			
			case .Requestable:
				sessionController.requestAuthorization(
				{
					(granted: Bool) -> Void in
						if granted {
							self.showCameraPreview()
						}
						else {
							self.showAccessDeniedMessage()
						}
				})
		}
	}
	
	func showCameraPreview()
	{
		sessionController.configureSession()
		
		let previewLayer = sessionController.previewLayer
		previewLayer.frame = previewView.bounds
		previewView.layer.masksToBounds = true
		previewView.layer.addSublayer(previewLayer)
		
		sessionController.startSession()
		
		sessionController.didDetectFacesHandler = {
			(faces) -> Void in
				self.prepareFaceViews(faces.count - self.faceViews.count)
			
				for (idx, face) in faces.enumerate() {
					self.faceViews[idx].frame = face.frame
				}
		}
	}
	
	func prepareFaceViews(diff:Int)
	{
		if diff > 0 {
			for _ in 0..<diff {
				let faceView = UIView(frame: CGRectZero)
				faceView.backgroundColor = UIColor.clearColor()
				faceView.layer.borderColor = UIColor.yellowColor().CGColor
				faceView.layer.borderWidth = 3.0
				facesView.addSubview(faceView)
				
				faceViews.append(faceView)
			}
		}
		else {
			for _ in 0..<abs(diff) {
				faceViews[0].removeFromSuperview()
				faceViews.removeAtIndex(0)
			}
		}
	}
	
	func showAccessDeniedMessage()
	{
		
	}
	
	func showAccessRestrictedMessage()
	{
		
	}
}
