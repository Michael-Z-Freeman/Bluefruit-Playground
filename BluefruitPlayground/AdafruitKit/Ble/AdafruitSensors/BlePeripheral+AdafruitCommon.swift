//
//  BlePeripehral+AdafruitCommon.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 13/11/2019.
//  Copyright © 2019 Adafruit. All rights reserved.
//

import Foundation
import CoreBluetooth

extension BlePeripheral {
    // Costants
    private static let kAdafruitMeasurementPeriodCharacteristicUUID = CBUUID(string: "ADAF0001-C332-42A8-93BD-25E905756CB8")
    private static let kAdafruitServiceVersionCharacteristicUUID = CBUUID(string: "ADAF0002-C332-42A8-93BD-25E905756CB8")

    private static let kAdafruitDefaultVersionValue = 1         // Used as default version value if version characteristic cannot be read

    static let kAdafruitSensorDefaultPeriod: TimeInterval = 0.2

    
    // MARK: - Errors
    enum PeripheralAdafruitError: Error {
        case invalidCharacteristic
        case enableNotifyFailed
        case disableNotifyFailed
        case unknownVersion
        case invalidResponseData
    }

    // MARK: - Service Actions
    func adafruitServiceEnable(serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID, completion: ((Result<(Int, CBCharacteristic), Error>) -> Void)?) {

        self.characteristic(uuid: mainCharacteristicUuid, serviceUuid: serviceUuid) { [weak self] (characteristic, error) in
            guard let characteristic = characteristic, error == nil else {
                completion?(.failure(error ?? PeripheralAdafruitError.invalidCharacteristic))
                return
            }

            guard let self = self else { return }

            // Check version
            self.adafruitVersion(serviceUuid: serviceUuid) { version in
                completion?(.success((version, characteristic)))
            }
        }
    }

    func adafruitServiceEnableIfVersion(version expectedVersion: Int, serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID,  completion: ((Result<CBCharacteristic, Error>) -> Void)?) {
        
        self.adafruitServiceEnable(serviceUuid: serviceUuid, mainCharacteristicUuid: mainCharacteristicUuid) { [weak self] result in
            self?.checkVersionResult(expectedVersion: expectedVersion, result: result, completion: completion)
        }
    }
    

    /**
            - parameters:
                - timePeriod: seconds between measurements. -1 to disable measurements

     */
    func adafruitServiceEnableIfVersion(version expectedVersion: Int, serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID, timePeriod: TimeInterval?, responseHandler: @escaping(Result<(Data, UUID), Error>) -> Void, completion: ((Result<CBCharacteristic, Error>) -> Void)?) {
        
        adafruitServiceEnableIfVersion(version: expectedVersion, serviceUuid: serviceUuid, mainCharacteristicUuid: mainCharacteristicUuid) { [weak self] result in
            
            switch result {
            case let .success(characteristic):      // Version supported
                self?.adafruitServiceSetRepeatingResponse(characteristic: characteristic, timePeriod: timePeriod, responseHandler: responseHandler, completion: { result in
                    switch result {
                    case .success:
                        completion?(.success(characteristic))
                    case let .failure(error):
                        completion?(.failure(error))
                    }
                })
                
            case let .failure(error):           // Unsupported version (or error)
                completion?(.failure(error))
            }
            
        }
    }
    
    private func adafruitServiceSetRepeatingResponse(characteristic: CBCharacteristic, timePeriod: TimeInterval?, responseHandler: @escaping(Result<(Data, UUID), Error>) -> Void, completion: ((Result<Void, Error>) -> Void)?) {
        
        // Prepare notification handler
        let notifyHandler: ((Error?) -> Void)? = { [weak self] error in
            guard error == nil else {
                responseHandler(.failure(error!))
                return
            }

            guard let self = self else { return }
            if let data = characteristic.value {
                responseHandler(.success((data, self.identifier)))
            }
        }
        
        // Refresh period handler
        let enableNotificationsHandler = {
            // Enable notifications
            if !characteristic.isNotifying {
                self.enableNotify(for: characteristic, handler: notifyHandler, completion: { error in
                    guard error == nil else {
                        completion?(.failure(error!))
                        return
                    }
                    guard characteristic.isNotifying else {
                        completion?(.failure(PeripheralAdafruitError.enableNotifyFailed))
                        return
                    }
                    
                    completion?(.success(()))
                    
                })
            } else {
                self.updateNotifyHandler(for: characteristic, handler: notifyHandler)
                completion?(.success(()))
            }
        }
        
        // Time period
        if let timePeriod = timePeriod, let serviceUuid = characteristic.service?.uuid {    // Set timePeriod if not nil
            
            self.adafruitSetPeriod(timePeriod, serviceUuid: serviceUuid) { result in
                if case let .failure(error) = result {
                    completion?(.failure(error))
                    return
                }
                
                if Config.isDebugEnabled {
                    // Check period
                    self.adafruitPeriod(serviceUuid: serviceUuid) { period in
                        guard period != nil else { DLog("Error setting service period"); return }
                        //DLog("service period: \(period!)")
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    enableNotificationsHandler()
                }
            }
        } else {        // Use default timePeriod
            enableNotificationsHandler()
        }
    }
    
    private func checkVersionResult(expectedVersion: Int, result: Result<(Int, CBCharacteristic), Error>, completion: ((Result<CBCharacteristic, Error>) -> Void)?) {
        switch result {
        case let .success((version, characteristic)):
            guard version == expectedVersion else {
                DLog("Warning: adafruitServiceEnableIfVersion unknown version: \(version). Expected: \(expectedVersion)")
                completion?(.failure(PeripheralAdafruitError.unknownVersion))
                return
            }
            
            completion?(.success(characteristic))
        case let .failure(error):
            completion?(.failure(error))
        }
    }
    
    func adafruitServiceDisable(serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID, completion: ((Result<Void, Error>) -> Void)?) {
        self.characteristic(uuid: mainCharacteristicUuid, serviceUuid: serviceUuid) { [weak self] (characteristic, error) in
            guard let characteristic = characteristic, error == nil else {
                completion?(.failure(error ?? PeripheralAdafruitError.invalidCharacteristic))
                return
            }
            
            let kDisablePeriod: TimeInterval = -1       // -1 means taht the updates will be disabled
            self?.adafruitSetPeriod(kDisablePeriod, serviceUuid: serviceUuid) { [weak self] result in
                // Disable notifications
                if characteristic.isNotifying {
                    self?.disableNotify(for: characteristic) { error in
                        guard error == nil else {
                            completion?(.failure(error!))
                            return
                        }
                        guard !characteristic.isNotifying else {
                            completion?(.failure(PeripheralAdafruitError.disableNotifyFailed))
                            return
                        }
                        
                        completion?(.success(()))
                    }
                }
                else {
                    completion?(result)
                }
            }
        }
    }

    func adafruitVersion(serviceUuid: CBUUID, completion: @escaping(Int) -> Void) {
        self.characteristic(uuid: BlePeripheral.kAdafruitServiceVersionCharacteristicUUID, serviceUuid: serviceUuid) { [weak self] (characteristic, error) in

            // Check if version characteristic exists or return default value
            guard error == nil, let characteristic = characteristic  else {
                completion(BlePeripheral.kAdafruitDefaultVersionValue)
                return
            }
            
            // Read the version
            self?.readCharacteristic(characteristic) { (result, error) in
                guard error == nil, let data = result as? Data, data.count >= 4 else {
                    completion(BlePeripheral.kAdafruitDefaultVersionValue)
                    return
                }
                
                let version = data.toIntFrom32Bits()
                completion(version)
            }
        }
    }

    func adafruitPeriod(serviceUuid: CBUUID, completion: @escaping(TimeInterval?) -> Void) {
        self.characteristic(uuid: BlePeripheral.kAdafruitMeasurementPeriodCharacteristicUUID, serviceUuid: serviceUuid) { (characteristic, error) in

            guard error == nil, let characteristic = characteristic else {
                completion(nil)
                return
            }

            self.readCharacteristic(characteristic) { (data, error) in
                guard error == nil, let data = data as? Data else {
                    completion(nil)
                    return
                }

                let period = TimeInterval(data.toIntFrom32Bits()) / 1000.0
                completion(period)
            }
        }
    }

    /**
        Set measurement period
             
        - parameters:
            - period: seconds between measurements. -1 to disable measurements

      */
    func adafruitSetPeriod(_ period: TimeInterval, serviceUuid: CBUUID, completion: ((Result<Void, Error>) -> Void)?) {

        self.characteristic(uuid: BlePeripheral.kAdafruitMeasurementPeriodCharacteristicUUID, serviceUuid: serviceUuid) { (characteristic, error) in

            guard error == nil, let characteristic = characteristic else {
                DLog("Error: adafruitSetPeriod: \(String(describing: error))")
                return
            }

            let periodMillis = period == -1 ? -1 : Int32(period * 1000)     // -1 means disable measurements. It is a special value
            let data = periodMillis.littleEndian.data
            self.write(data: data, for: characteristic, type: .withResponse) { error in
                guard error == nil else {
                    DLog("Error: adafruitSetPeriod \(error!)")
                    completion?(.failure(error!))
                    return
                }

                completion?(.success(()))
            }
        }
    }
    
    // MARK: - Utils
    func adafruitDataToFloatArray(_ data: Data) -> [Float]? {
        let unitSize = MemoryLayout<UInt32>.size
        guard data.count % unitSize == 0 else { return nil }

        return stride(from: 0, to: data.count, by: unitSize).map { offset in
            let bits = data.withUnsafeBytes { rawBuffer -> UInt32 in
                rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            return Float(bitPattern: UInt32(littleEndian: bits))
        }
    }
    
    func adafruitDataToUInt16Array(_ data: Data) -> [UInt16]? {
        let unitSize = MemoryLayout<UInt16>.size
        guard data.count % unitSize == 0 else { return nil }

        return stride(from: 0, to: data.count, by: unitSize).map { offset in
            let word = data.withUnsafeBytes { rawBuffer -> UInt16 in
                rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            }
            return UInt16(littleEndian: word)
        }
    }
    
    func adafruitDataToInt16Array(_ data: Data) -> [Int16]? {
        let unitSize = MemoryLayout<Int16>.size
        guard data.count % unitSize == 0 else { return nil }

        return stride(from: 0, to: data.count, by: unitSize).map { offset in
            let word = data.withUnsafeBytes { rawBuffer -> UInt16 in
                rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            }
            return Int16(bitPattern: UInt16(littleEndian: word))
        }
    }
}
