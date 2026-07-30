//
//  AccelerometerViewController.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 25/10/2019.
//  Copyright © 2019 Adafruit. All rights reserved.
//

import UIKit
import SceneKit

class AccelerometerViewController: ModuleViewController {
    // Constants
    static let kIdentifier = "AccelerometerViewController"

    // UI
    @IBOutlet weak var sceneView: SCNView!

    // Data
    private var acceleration: BlePeripheral.AccelerometerValue?
    private var boardNode: SCNNode?
    private var valuesPanelViewController: AccelerometerPanelViewController!

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        // Add panels 
        valuesPanelViewController = (addPanelViewController(storyboardIdentifier: AccelerometerPanelViewController.kIdentifier) as! AccelerometerPanelViewController)
        
        // Load scene
        if let scene = AdafruitBoardsManager.shared.currentBoard?.assetScene {
            boardNode = scene.rootNode.childNode(withName: "root", recursively: false)
            
            // Setup scene
            sceneView.scene = scene
            if let pointOfView = scene.rootNode.childNode(withName: "camera", recursively: true) {
                sceneView.pointOfView = pointOfView
            }
            sceneView.autoenablesDefaultLighting = true
            sceneView.isUserInteractionEnabled = true
        }
        
        // Localization
        let localizationManager = LocalizationManager.shared
        self.title = localizationManager.localizedString("accelerometer_title")
        moduleHelpMessage = localizationManager.localizedString("accelerometer_help")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Initial value
        let board = AdafruitBoardsManager.shared.currentBoard
        if let acceleration = board?.accelerometerLastValue() {
            self.acceleration = acceleration
        }
        SCNTransaction.animationDuration = 0        // The first render should be inmediate and not animated
        updateValueUI()

        // Set delegate
        board?.accelerometerDelegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remove delegate
        let board = AdafruitBoardsManager.shared.currentBoard
        board?.accelerometerDelegate = nil
    }

    // MARK: - UI
    private func updateValueUI() {
        guard let acceleration = acceleration else { return }
        
        SCNTransaction.animationDuration = BlePeripheral.kAdafruitSensorDefaultPeriod
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)

        // Calculate Euler Angles
        let eulerAngles = AccelerometerUtils.accelerationToEuler(acceleration)
        //DLog("Euler: pitch: \(eulerAngles.x) yaw: \(eulerAngles.y) roll: \(eulerAngles.z)")

        // Update circuit model orientation
        boardNode?.eulerAngles = eulerAngles

        // Update panel
        valuesPanelViewController.accelerationReceived(acceleration: acceleration, eulerAngles: eulerAngles)
    }
}

// MARK: - CPBBleAccelerometerDelegate
extension AccelerometerViewController: AdafruitAccelerometerDelegate {
    func adafruitAccelerationReceived(_ acceleration: BlePeripheral.AccelerometerValue) {
        self.acceleration = acceleration
        updateValueUI()
    }
}

final class GyroscopeViewController: UIViewController {
    private let xValueLabel = GyroscopeViewController.valueLabel()
    private let yValueLabel = GyroscopeViewController.valueLabel()
    private let zValueLabel = GyroscopeViewController.valueLabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = LocalizationManager.shared.localizedString("gyroscope_title")
        view.backgroundColor = UIColor(named: "main")

        let stack = UIStackView(arrangedSubviews: [
            axisRow(title: "X", valueLabel: xValueLabel),
            axisRow(title: "Y", valueLabel: yValueLabel),
            axisRow(title: "Z", valueLabel: zValueLabel)
        ])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let board = AdafruitBoardsManager.shared.currentBoard
        board?.gyroscopeDelegate = self
        if let value = board?.gyroscopeLastValue() {
            update(value)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AdafruitBoardsManager.shared.currentBoard?.gyroscopeDelegate = nil
    }

    private func axisRow(title: String, valueLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = UIColor(named: "text_default")

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .center
        return row
    }

    private static func valueLabel() -> UILabel {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        label.textColor = UIColor(named: "text_default")
        label.text = "--"
        return label
    }

    private func update(_ value: BlePeripheral.GyroscopeValue) {
        xValueLabel.text = String(format: "%.3f rad/s", value.x)
        yValueLabel.text = String(format: "%.3f rad/s", value.y)
        zValueLabel.text = String(format: "%.3f rad/s", value.z)
    }
}

extension GyroscopeViewController: AdafruitGyroscopeDelegate {
    func adafruitGyroscopeReceived(_ gyroscope: BlePeripheral.GyroscopeValue) {
        update(gyroscope)
    }
}
