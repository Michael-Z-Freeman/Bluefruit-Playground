//
//  AdafruitBoard+Assets.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 12/03/2020.
//  Copyright © 2020 Adafruit. All rights reserved.
//

import UIKit
import SceneKit

extension AdafruitBoard {
    
    var assetScene: SCNScene? {
        if model == .feather_nRF52840_sense {
            return featherSenseScene()
        }

        var filename: String?
        if let model = self.model {
            switch model {
            case .circuitPlaygroundBluefruit:
                filename = "cpb.scn"
            case .clue_nRF52840:
                filename = "clue.scn"
            default:
                filename = nil
            }
        }
        
        let scene: SCNScene?
        if let filename = filename {
            scene = SCNScene(named: filename)
            scene?.background.contents = UIColor.clear
        }
        else {
            scene = nil
        }
                
        return scene
    }
    
    var assetFrontImage: UIImage? {
        return AdafruitBoard.assetFrontImage(model: model)
    }
    
    static func assetFrontImage(model: BlePeripheral.AdafruitManufacturerData.BoardModel?) -> UIImage? {
        guard let model = model else { return nil }

        var name: String?

        switch model {
        case .circuitPlaygroundBluefruit:
            name = "board_cpb"
        case .clue_nRF52840:
            name = "board_clue_front"
        default:
            name = nil
        }
        
        return name == nil ? nil : UIImage(named: name!)
    }

    private func featherSenseScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let root = SCNNode()
        root.name = "root"
        scene.rootNode.addChildNode(root)

        let board = SCNBox(width: 0.055, height: 0.003, length: 0.09, chamferRadius: 0.002)
        board.firstMaterial?.diffuse.contents = UIColor(red: 0.04, green: 0.32, blue: 0.19, alpha: 1)
        let boardNode = SCNNode(geometry: board)
        root.addChildNode(boardNode)

        let usb = SCNBox(width: 0.018, height: 0.005, length: 0.008, chamferRadius: 0.001)
        usb.firstMaterial?.diffuse.contents = UIColor.lightGray
        let usbNode = SCNNode(geometry: usb)
        usbNode.position = SCNVector3(0, 0.004, -0.047)
        root.addChildNode(usbNode)

        let sensor = SCNBox(width: 0.012, height: 0.004, length: 0.012, chamferRadius: 0.001)
        sensor.firstMaterial?.diffuse.contents = UIColor.black
        let sensorNode = SCNNode(geometry: sensor)
        sensorNode.position = SCNVector3(0.012, 0.004, 0.008)
        root.addChildNode(sensorNode)

        let camera = SCNCamera()
        camera.orthographicScale = 0.11
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.12, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let light = SCNLight()
        light.type = .ambient
        light.intensity = 900
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
        return scene
    }
}
