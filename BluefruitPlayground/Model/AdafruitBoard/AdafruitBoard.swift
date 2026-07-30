//
//  AdafruitBoard.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 26/10/2019.
//  Copyright © 2019 Adafruit. All rights reserved.
//

import UIKit
import FlexColorPicker
import CoreBluetooth


// Delegates for each sensor
protocol AdafruitTemperatureDelegate: AnyObject {
    func adafruitTemperatureReceived(_ temperature: Float)
}

protocol AdafruitLightDelegate: AnyObject {
    func adafruitLightReceived(_ light: Float)
}

protocol AdafruitButtonsDelegate: AnyObject {
    func adafruitButtonsReceived(_ buttonsState: BlePeripheral.ButtonsState)
}

protocol AdafruitAccelerometerDelegate: AnyObject {
    func adafruitAccelerationReceived(_ acceleration: BlePeripheral.AccelerometerValue)
}

protocol AdafruitHumidityDelegate: AnyObject {
    func adafruitHumidityReceived(_ humidity: Float)
}

protocol AdafruitBarometricPressureDelegate: AnyObject {
    func adafruitBarometricPressureReceived(_ pressure: Float)
}

protocol AdafruitSoundDelegate: AnyObject {
    func adafruitSoundReceived(_ channelSamples: [Double])
}

protocol AdafruitGyroscopeDelegate: AnyObject {
    func adafruitGyroscopeReceived(_ gyroscope: BlePeripheral.GyroscopeValue)
}

protocol AdafruitQuaternionDelegate: AnyObject {
    func adafruitQuaternionReceived(_ quaternion: BlePeripheral.QuaternionValue)
}

/**
 Manages the sensors for a connected Adafruit Board
 
 Use setupPeripheral to bind it to a connected BlePeripheral. setupPeripheral verifies the that sensor firmware version is supported, sets the period for receving data and starts sending the recevied data to the delegate and the NotificationCenter
 
 - Supported sensors:
 - neopixels
 - light
 - buttons
 - tone generator
 - accelerometer
 - temperature
 - humidity
 - barometric pressure
 - sound
 
 */
class AdafruitBoard {
    // Constants
    private static let kLightSequenceFramesPerSecond = 10
    private static let kLightSequenceDefaultBrightness: CGFloat = 0.25
    public static let kLightSequenceDefaultSpeed: Double = 0.3
    
    // Data structs
    enum BoardError: Error {
        case errorBoardNotConnected
        case errorDiscoveringServices
    }
    
    enum BoardService: CaseIterable, Hashable {
        case neopixels
        case light
        case buttons
        case toneGenerator
        case accelerometer
        case temperature
        case humidity
        case barometricPressure
        case sound
        case gyroscope
        case quaternion
        
        var debugName: String {
            switch self {
            case .neopixels: return "Neopixels"
            case .light: return "Light"
            case .buttons: return "Buttons"
            case .toneGenerator: return "ToneGenerator"
            case .accelerometer: return "Accelerometer"
            case .temperature: return "Temperature"
            case .humidity: return "Humidity"
            case .barometricPressure: return "Barometric Pressure"
            case .sound: return "Sound"
            case .gyroscope: return "Gyroscope"
            case .quaternion: return "Quaternion"
            }
        }

        var serviceUuid: CBUUID {
            switch self {
            case .neopixels: return BlePeripheral.kAdafruitNeoPixelsServiceUUID
            case .light: return BlePeripheral.kAdafruitLightServiceUUID
            case .buttons: return BlePeripheral.kAdafruitButtonsServiceUUID
            case .toneGenerator: return BlePeripheral.kAdafruitToneGeneratorServiceUUID
            case .accelerometer: return BlePeripheral.kAdafruitAccelerometerServiceUUID
            case .temperature: return BlePeripheral.kAdafruitTemperatureServiceUUID
            case .humidity: return BlePeripheral.kAdafruitHumidityServiceUUID
            case .barometricPressure: return BlePeripheral.kAdafruitBarometricPressureServiceUUID
            case .sound: return BlePeripheral.kAdafruitSoundSensorServiceUUID
            case .gyroscope: return BlePeripheral.kAdafruitGyroscopeServiceUUID
            case .quaternion: return BlePeripheral.kAdafruitQuaternionServiceUUID
            }
        }
    }
    
    // Notifications
    enum NotificationUserInfoKey: String {
        case uuid = "uuid"
        case value = "value"
    }
    
    // Params - Delegates
    weak var lightDelegate: AdafruitLightDelegate?
    weak var accelerometerDelegate: AdafruitAccelerometerDelegate?
    weak var buttonsDelegate: AdafruitButtonsDelegate?
    weak var temperatureDelegate: AdafruitTemperatureDelegate?
    weak var humidityDelegate: AdafruitHumidityDelegate?
    weak var barometricPressureDelegate: AdafruitBarometricPressureDelegate?
    weak var soundDelegate: AdafruitSoundDelegate?
    weak var gyroscopeDelegate: AdafruitGyroscopeDelegate?
    weak var quaternionDelegate: AdafruitQuaternionDelegate?

    // Params - Data Series
    var isLightDataSeriesEnabled = true
    var isAccelerometerDataSeriesEnabled = false
    var isTemperatureDataSeriesEnabled = true
    var isHumidityDataSeriesEnabled = true
    var isBarometricPressureDataSeriesEnabled = true
    var isSoundAmplitudePressureDataSeriesEnabled = true
    var isGyroscopeDataSeriesEnabled = false
    var isQuaternioDataSeriesEnabled = false

    // Params - Specific behaviour
    var accelerometerAutoAdjustOrientation = true           // If true, the orientation will be modified to show the board correctly taking into account where the sensor is located in the board

    var quaternionAutoAdjustOrientation = true           // If true, the orientation will be modified to show the board correctly taking into account where the sensor is located in the board

    // Data
    private(set) weak var blePeripheral: BlePeripheral?
    private(set) var unavailableServices = Set<BoardService>()
    var model: BlePeripheral.AdafruitManufacturerData.BoardModel? {
        return blePeripheral?.adafruitManufacturerData()?.boardModel
    }

    // Data - DataSeries
    private(set) var lightDataSeries = SensorDataSeries<Float>()
    private(set) var accelerometerDataSeries = SensorDataSeries<BlePeripheral.AccelerometerValue>()
    private(set) var temperatureDataSeries = SensorDataSeries<Float>()
    private(set) var humidityDataSeries = SensorDataSeries<Float>()
    private(set) var barometricPressureDataSeries = SensorDataSeries<Float>()
    private(set) var soundAmplitudeDataSeries = SensorDataSeries<Float>()
    private(set) var gyroscopeDataSeries = SensorDataSeries<BlePeripheral.GyroscopeValue>()
    private(set) var quaternionDataSeries = SensorDataSeries<BlePeripheral.QuaternionValue>()

    // Data - Neopixel specific
    private var currentLightSequenceAnimation: LightSequenceAnimation?
    public var neopixelCurrentLightSequenceAnimationSpeed: Double {
        get {
            return currentLightSequenceAnimation?.speed ?? 0
        }
        
        set {
            currentLightSequenceAnimation?.speed = newValue
        }
    }
    
    
    // MARK: - Setup
    
    /**
     Setup the singleton to use a BlePeripheral
     
     - parameters:
     - blePeripheral: a *connected* BlePeripheral
     - services: list of BoardServices that will be started. Use nil to select all the supported services
     - completion: completion handler
     */
    func setupPeripheral(blePeripheral: BlePeripheral, services: [BoardService]? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        
        DLog("Discovering services")
        let boardModel = blePeripheral.adafruitManufacturerData()?.boardModel
        let selectedServices = services ?? defaultServices(for: boardModel)
        let serviceUuidsToDiscover = shouldDiscoverOnlyKnownServices(for: boardModel) ? selectedServices.map { $0.serviceUuid } : nil
        if Config.isDebugEnabled {
            DLog("Board model: \(String(describing: boardModel)); services: \(selectedServices.map { $0.debugName }.joined(separator: ", "))")
        }
        let peripheralIdentifier = blePeripheral.identifier
        NotificationCenter.default.post(name: .willDiscoverServices, object: nil, userInfo: [NotificationUserInfoKey.uuid.rawValue: peripheralIdentifier])
        blePeripheral.discover(serviceUuids: serviceUuidsToDiscover) { error in
            // Check errors
            guard error == nil else {
                DLog("Error discovering services")
                DispatchQueue.main.async {
                    completion(.failure(BoardError.errorDiscoveringServices))
                }
                return
            }
            
            // Setup services
            self.setupServices(blePeripheral: blePeripheral, services: selectedServices, completion: completion)
        }
    }

    private func defaultServices(for model: BlePeripheral.AdafruitManufacturerData.BoardModel?) -> [BoardService] {
        switch model {
        case .feather_nRF52840_sense:
            return [.neopixels, .light, .buttons, .accelerometer, .temperature, .humidity, .barometricPressure, .sound, .gyroscope, .quaternion]
        default:
            return BoardService.allCases
        }
    }

    private func shouldDiscoverOnlyKnownServices(for model: BlePeripheral.AdafruitManufacturerData.BoardModel?) -> Bool {
        switch model {
        case .feather_nRF52840_sense:
            return true
        default:
            return false
        }
    }
    
    private func setupServices(blePeripheral: BlePeripheral, services: [BoardService], completion: @escaping (Result<Void, Error>) -> Void) {
        
        // Set current peripheral
        self.blePeripheral = blePeripheral
        unavailableServices.removeAll()
        
        setupServices(blePeripheral: blePeripheral, remainingServices: services, enabledServices: [], completion: completion)
    }

    private func setupServices(blePeripheral: BlePeripheral, remainingServices: [BoardService], enabledServices: [BoardService], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let service = remainingServices.first else {
            DLog("setupServices finished")

            if Config.isDebugEnabled {
                for service in enabledServices {
                    DLog(self.isEnabled(service: service) ? "\(service.debugName) reading enabled":"\(service.debugName) service not available")
                }
            }

            completion(.success(()))
            return
        }

        let next: (Result<Void, Error>) -> Void = { result in
            let remaining = Array(remainingServices.dropFirst())
            var enabled = enabledServices

            switch result {
            case .success:
                enabled.append(service)
            case let .failure(error):
                self.unavailableServices.insert(service)
                DLog("Unable to enable \(service.debugName): \(error.localizedDescription)")

                guard blePeripheral.state == .connected else {
                    completion(.failure(BoardError.errorBoardNotConnected))
                    return
                }
            }

            self.setupServices(blePeripheral: blePeripheral, remainingServices: remaining, enabledServices: enabled, completion: completion)
        }

        if Config.isDebugEnabled {
            DLog("Enabling \(service.debugName)")
        }

        switch service {
        case .neopixels:
            blePeripheral.adafruitNeoPixelsEnable(completion: next)
        case .light:
            blePeripheral.adafruitLightEnable(responseHandler: self.receiveLightData, completion: next)
        case .buttons:
            blePeripheral.adafruitButtonsEnable(responseHandler: self.receiveButtonsData, completion: next)
        case .toneGenerator:
            blePeripheral.adafruitToneGeneratorEnable(completion: next)
        case .accelerometer:
            blePeripheral.adafruitAccelerometerEnable(responseHandler: self.receiveAccelerometerData, completion: next)
        case .temperature:
            blePeripheral.adafruitTemperatureEnable(responseHandler: self.receiveTemperatureData, completion: next)
        case .humidity:
            blePeripheral.adafruitHumidityEnable(responseHandler: self.receiveHumidityData, completion: next)
        case .barometricPressure:
            blePeripheral.adafruitBarometricPressureEnable(responseHandler: self.receiveBarometricPressureData, completion: next)
        case .sound:
            blePeripheral.adafruitSoundEnable(responseHandler: self.receiveSoundData) { result in
                switch result {
                case .success:
                    next(.success(()))
                case let .failure(error):
                    next(.failure(error))
                }
            }
        case .gyroscope:
            blePeripheral.adafruitGyroscopeEnable(responseHandler: self.receiveGyroscopeData, completion: next)
        case .quaternion:
            blePeripheral.adafruitQuaternionEnable(responseHandler: self.receiveQuaternionData, completion: next)
        }
    }


    // MARK: - Sensor availability
    var isNeopixelsEnabled: Bool {
        return blePeripheral?.adafruitNeoPixelsIsEnabled() ?? false
    }
    
    var isLightEnabled: Bool {
        return blePeripheral?.adafruitLightIsEnabled() ?? false
    }
    
    var isButtonsEnabled: Bool {
        return blePeripheral?.adafruitButtonsIsEnabled() ?? false
    }
    
    var isToneGeneratorEnabled: Bool {
        return blePeripheral?.adafruitToneGeneratorIsEnabled() ?? false
    }
    
    var isAccelerometerEnabled: Bool {
        return blePeripheral?.adafruitAccelerometerIsEnabled() ?? false
    }
    
    var isTemperatureEnabled: Bool {
        return blePeripheral?.adafruitTemperatureIsEnabled() ?? false
    }
    
    var isHumidityEnabled: Bool {
        return blePeripheral?.adafruitHumidityIsEnabled() ?? false
    }
    
    var isBarometricPressureEnabled: Bool {
        return blePeripheral?.adafruitBarometricPressureIsEnabled() ?? false
    }
    
    var isSoundEnabled: Bool {
        return blePeripheral?.adafruitSoundIsEnabled() ?? false
    }

    var isGyroscopeEnabled: Bool {
        return blePeripheral?.adafruitGyroscopeIsEnabled() ?? false
    }

    var isQuaternionEnabled: Bool {
        return blePeripheral?.adafruitQuaternionIsEnabled() ?? false
    }
    
    func isEnabled(service: BoardService) -> Bool {
        switch service {
        case .neopixels: return isNeopixelsEnabled
        case .light: return isLightEnabled
        case .buttons: return isButtonsEnabled
        case .toneGenerator: return isToneGeneratorEnabled
        case .accelerometer: return isAccelerometerEnabled
        case .temperature: return isTemperatureEnabled
        case .humidity: return isHumidityEnabled
        case .barometricPressure: return isBarometricPressureEnabled
        case .sound: return isSoundEnabled
        case .gyroscope: return isGyroscopeEnabled
        case .quaternion: return isQuaternionEnabled
        }
    }
    
    // MARK: - Read Data
    var neopixelPixelsCount: Int? {
        return blePeripheral?.adafruitNeoPixelsCount
    }
    
    func lightLastValue() -> Float? {
        return blePeripheral?.adafruitLightLastValue()
    }
    
    func buttonsReadState(completion: @escaping(Result<(BlePeripheral.ButtonsState, UUID), Error>) -> Void) {
        blePeripheral?.adafruitButtonsReadState() { result in
            DispatchQueue.main.async {      // Send response in main thread
                completion(result)
            }
        }
    }
    
    func buttonsLastValue() -> BlePeripheral.ButtonsState? {
        return blePeripheral?.adafruitButtonsLastValue()
    }
    
    func accelerometerLastValue() -> BlePeripheral.AccelerometerValue? {
        return blePeripheral?.adafruitAccelerometerLastValue()
    }
    
    func temperatureLastValue() -> Float? {
        return blePeripheral?.adafruitTemperatureLastValue()
    }
    
    func humidityLastValue() -> Float? {
        return blePeripheral?.adafruitHumidityLastValue()
    }
    
    func barometricPressureLastValue() -> Float? {
        return blePeripheral?.adafruitBarometricPressureLastValue()
    }
    
    func soundLastAmplitudesPerChannel() -> [Double]? {
        return blePeripheral?.adafruitSoundLastAmplitudePerChannel()
    }
    
    func soundLastAmplitude() -> Double? {
        return soundLastAmplitudesPerChannel()?.first
    }
    
    func gyroscopeLastValue() -> BlePeripheral.GyroscopeValue? {
        return blePeripheral?.adafruitGyroscopeLastValue()
    }

    func quaternionLastValue() -> BlePeripheral.QuaternionValue? {
        return blePeripheral?.adafruitQuaternionLastValue()
    }
    
    
    // MARK: - Receive Data
    private func receiveLightData(response: Result<(Float, UUID), Error>) {
        switch response {
        case let .success((light, uuid)):
            
            if isLightDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: light, timestamp: CFAbsoluteTimeGetCurrent())
                lightDataSeries.addValue(entry)
                //DLog("Light (lux): \(light)")
            }
            
            // Send to delegate
            if let lightDelegate = lightDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    lightDelegate.adafruitLightReceived(light)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveLightData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: light,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving light data: \(error)")
        }
    }
    
    private func receiveButtonsData(response: Result<(BlePeripheral.ButtonsState, UUID), Error>) {
        switch response {
        case let .success((buttonsState, uuid)):
            //DLog("Buttons: \(buttonsState.slideSwitch == .left ? "⬅️":"➡️") \(buttonsState.buttonA == .pressed ? "🔳":"🔲") \(buttonsState.buttonB == .pressed ? "🔳":"🔲") ")
            
            // Send to delegate
            if let buttonsDelegate = buttonsDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    buttonsDelegate.adafruitButtonsReceived(buttonsState)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveButtonsData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: buttonsState,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving light data: \(error)")
        }
    }
    
    private func receiveAccelerometerData(response: Result<(BlePeripheral.AccelerometerValue, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            var adjustedAcceleration = value
            
            if accelerometerAutoAdjustOrientation {
                if model == .clue_nRF52840 {        // Clue has the accelerometer in the back
                    adjustedAcceleration.x = -value.x
                    adjustedAcceleration.z = -value.z
                }
            }
            
            if isAccelerometerDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: adjustedAcceleration, timestamp: CFAbsoluteTimeGetCurrent())
                accelerometerDataSeries.addValue(entry)
                //DLog("Accelerometer x: \(adjustedAcceleration.x), y: \(adjustedAcceleration.y) z: \(adjustedAcceleration.z)")
            }
            
            // Send to delegate
            if let accelerometerDelegate = accelerometerDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    accelerometerDelegate.adafruitAccelerationReceived(adjustedAcceleration)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveAccelerometerData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: adjustedAcceleration,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving accelerometer data: \(error)")
        }
    }
    
    private func receiveTemperatureData(response: Result<(Float, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            
            if isTemperatureDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: value, timestamp: CFAbsoluteTimeGetCurrent())
                temperatureDataSeries.addValue(entry)
                //DLog("Temperature (ºC): \(temperature)")
            }
            
            // Send to delegate
            if let temperatureDelegate = temperatureDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    temperatureDelegate.adafruitTemperatureReceived(value)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveTemperatureData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: value,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving temperature data: \(error)")
        }
    }
    
    private func receiveHumidityData(response: Result<(Float, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            
            if isHumidityDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: value, timestamp: CFAbsoluteTimeGetCurrent())
                humidityDataSeries.addValue(entry)
                //DLog("Humidity: \(humidity)%")
            }
            
            // Send to delegate
            if let humidityDelegate = humidityDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    humidityDelegate.adafruitHumidityReceived(value)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveHumidityData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: value,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving humidity data: \(error)")
        }
    }
    
    private func receiveBarometricPressureData(response: Result<(Float, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            
            if isBarometricPressureDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: value, timestamp: CFAbsoluteTimeGetCurrent())
                barometricPressureDataSeries.addValue(entry)
                //DLog("Pressure: \(pressure)hPa")
            }
            
            // Send to delegate
            if let barometricPressureDelegate = barometricPressureDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    barometricPressureDelegate.adafruitBarometricPressureReceived(value)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveBarometricPressureData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: value,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving pressure data: \(error)")
        }
    }
    
    private func receiveSoundData(response: Result<([Double], UUID), Error>) {
        switch response {
        case let .success((amplitudesPerChannel, uuid)):
            
            if isSoundAmplitudePressureDataSeriesEnabled {
                // Save value
                if let amplitude = amplitudesPerChannel.first, amplitude.isFinite {     // - Infinite values are not added to the dataSeries
                    let entry = SensorDataSeries.Entry(value: Float(amplitude), timestamp: CFAbsoluteTimeGetCurrent())
                    soundAmplitudeDataSeries.addValue(entry)
                    //DLog("Amplitude: \(amplitude)dBFS")
                }
            }
            
            // Send to delegate
            if let soundDelegate = soundDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    soundDelegate.adafruitSoundReceived(amplitudesPerChannel)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveSoundData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: amplitudesPerChannel,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving sound data: \(error)")
        }
    }
    
    private func receiveGyroscopeData(response: Result<(BlePeripheral.GyroscopeValue, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            
            if isGyroscopeDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: value, timestamp: CFAbsoluteTimeGetCurrent())
                gyroscopeDataSeries.addValue(entry)
                DLog("Gyroscope x: \(value.x), y: \(value.y) z: \(value.z)")
            }
            
            // Send to delegate
            if let gyroscopeDelegate = gyroscopeDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    gyroscopeDelegate.adafruitGyroscopeReceived(value)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveGyroscopeData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: value,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving gyroscope data: \(error)")
        }
    }
    
    private func receiveQuaternionData(response: Result<(BlePeripheral.QuaternionValue, UUID), Error>) {
        switch response {
        case let .success((value, uuid)):
            var adjustedQuaternion = value
                      if quaternionAutoAdjustOrientation {
                          if model == .clue_nRF52840 {        // Clue has the quaternion sensor in the back
                            adjustedQuaternion = QuaternionUtils.quaternionRotated(quaternion: value, angle: .pi, axis: (x: Float(0), y: Float(1), z: Float(0)))
                          }
                      }
            
            if isQuaternioDataSeriesEnabled {
                // Save value
                let entry = SensorDataSeries.Entry(value: adjustedQuaternion, timestamp: CFAbsoluteTimeGetCurrent())
                quaternionDataSeries.addValue(entry)
                //DLog("Quaternion qx: \(value.qx), qy: \(value.qy) qz: \(value.qz) qw: \(value.qw)")
            }
            
            // Send to delegate
            if let quaternionDelegate = quaternionDelegate {
                DispatchQueue.main.async {      // Delegates are called in the main thread
                    quaternionDelegate.adafruitQuaternionReceived(adjustedQuaternion)
                }
            }
            
            // Send notification
            NotificationCenter.default.post(name: .didReceiveQuaternionData, object: nil, userInfo: [
                NotificationUserInfoKey.value.rawValue: adjustedQuaternion,
                NotificationUserInfoKey.uuid.rawValue: uuid
            ])
            
        case .failure(let error):
            DLog("Error receiving quaternion data: \(error)")
        }
    }
    
    // MARK: - Send Commands
    // MARK: Send Neopixel
    func neopixelSetAllPixelsColor(_ color: UIColor) {
        neopixelStopLightSequence()
        blePeripheral?.adafruitNeoPixelSetAllPixelsColor(color)
    }
    
    func neopixelSetPixelColor(_ color: UIColor, pixelMask: [Bool]) {
        neopixelStopLightSequence()
        blePeripheral?.adafruitNeoPixelSetColor(index: 0, color: color, pixelMask: pixelMask)
    }
    
    func neopixelStartLightSequence(_ lightSequenceGenerator: LightSequenceGenerator,
                                    framesPerSecond: Int = AdafruitBoard.kLightSequenceFramesPerSecond,
                                    speed: Double = AdafruitBoard.kLightSequenceDefaultSpeed,
                                    brightness: CGFloat = AdafruitBoard.kLightSequenceDefaultBrightness,
                                    repeating: Bool = true,
                                    sendLightSequenceNotifications: Bool = true) {
        neopixelStopLightSequence()
        
        currentLightSequenceAnimation = LightSequenceAnimation(lightSequenceGenerator: lightSequenceGenerator, framesPerSecond: framesPerSecond, repeating: repeating)
        currentLightSequenceAnimation!.speed = speed
        currentLightSequenceAnimation!.start(stopHandler: { [weak self] in
            self?.blePeripheral?.adafruitNeoPixelSetAllPixelsColor(.clear)
            }, frameHandler: { [weak self] pixelsBytes in
                guard let self = self else { return }
                guard let blePeripheral = self.blePeripheral else { return }
                
                let pixelBytesAdjustingBrightness = pixelsBytes.map {[
                    UInt8(CGFloat($0[0]) * brightness),
                    UInt8(CGFloat($0[1]) * brightness),
                    UInt8(CGFloat($0[2]) * brightness)
                    ]}
                
                let lightData = pixelBytesAdjustingBrightness.reduce(Data()) { (data, element) in
                    data + element.data
                }
                blePeripheral.adafruitNeoPixelsWriteData(offset: 0, pixelData: lightData)
                
                // Send notification
                if sendLightSequenceNotifications {
                    NotificationCenter.default.post(name: .didUpdateNeopixelLightSequence, object: nil, userInfo: [
                        NotificationUserInfoKey.value.rawValue: pixelsBytes,
                        NotificationUserInfoKey.uuid.rawValue: blePeripheral.identifier
                    ])
                }
        })
    }
    
    func neopixelStopLightSequence() {
        currentLightSequenceAnimation?.stop()
        currentLightSequenceAnimation = nil
    }
    
    // MARK: Send ToneGenerator
    func toneGeneratorStartPlaying(frequency: UInt16) {
        blePeripheral?.adafruitToneGeneratorStartPlaying(frequency: frequency)
    }
    
    func toneGeneratorStopPlaying() {
        blePeripheral?.adafruitToneGeneratorStartPlaying(frequency: 0)
    }
}

// MARK: - Custom Notifications
extension Notification.Name {
    private static let kNotificationsPrefix = Bundle.main.bundleIdentifier!
    static let willDiscoverServices = Notification.Name(kNotificationsPrefix+".willDiscoverServices")
    
    static let didUpdateNeopixelLightSequence = Notification.Name(kNotificationsPrefix+".didUpdateNeopixelLightSequence")
    static let didReceiveLightData = Notification.Name(kNotificationsPrefix+".didReceiveLightData")
    static let didReceiveButtonsData = Notification.Name(kNotificationsPrefix+".didReceiveButtonsData")
    static let didReceiveAccelerometerData = Notification.Name(kNotificationsPrefix+".didReceiveAccelerometerData")
    static let didReceiveHumidityData = Notification.Name(kNotificationsPrefix+".didReceiveHumidityData")
    static let didReceiveTemperatureData = Notification.Name(kNotificationsPrefix+".didReceiveTemperatureData")
    static let didReceiveBarometricPressureData = Notification.Name(kNotificationsPrefix+".didReceiveBarometricPressureData")
    static let didReceiveSoundData = Notification.Name(kNotificationsPrefix+".didReceiveSoundData")
    static let didReceiveGyroscopeData = Notification.Name(kNotificationsPrefix+".didReceiveGyroscopeData")
    static let didReceiveQuaternionData = Notification.Name(kNotificationsPrefix+".didReceiveQuaternionData")
}
