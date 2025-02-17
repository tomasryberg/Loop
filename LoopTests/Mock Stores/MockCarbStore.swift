//
//  MockCarbStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
@testable import Loop

class MockCarbStore: CarbStoreProtocol {
    var carbHistory: [StoredCarbEntry]?

    init(for scenario: DosingTestScenario = .flatAndStable) {
        self.scenario = scenario // The store returns different effect values based on the scenario
        self.carbHistory = loadHistoricCarbEntries(scenario: scenario)
    }
    
    var scenario: DosingTestScenario
    
    var sampleType: HKSampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.dietaryCarbohydrates)!
    
    var preferredUnit: HKUnit! = .gram()
    
    var delegate: CarbStoreDelegate?
    
    var carbRatioSchedule: CarbRatioSchedule?
    
    var insulinSensitivitySchedule: InsulinSensitivitySchedule?
    
    var insulinSensitivityScheduleApplyingOverrideHistory: InsulinSensitivitySchedule? = InsulinSensitivitySchedule(
        unit: HKUnit.milligramsPerDeciliter,
        dailyItems: [
            RepeatingScheduleValue(startTime: 0.0, value: 45.0),
            RepeatingScheduleValue(startTime: 32400.0, value: 55.0)
        ],
        timeZone: .utcTimeZone
    )!
    
    var carbRatioScheduleApplyingOverrideHistory: CarbRatioSchedule? = CarbRatioSchedule(
        unit: .gram(),
        dailyItems: [
            RepeatingScheduleValue(startTime: 0.0, value: 10.0),
            RepeatingScheduleValue(startTime: 32400.0, value: 12.0)
        ],
        timeZone: .utcTimeZone
    )!
    
    var maximumAbsorptionTimeInterval: TimeInterval {
        return defaultAbsorptionTimes.slow * 2
    }
    
    var delta: TimeInterval = .minutes(5)
    
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes = (fast: .minutes(30), medium: .hours(3), slow: .hours(5))
    
    var authorizationRequired: Bool = false
    
    var sharingDenied: Bool = false
    
    func authorize(toShare: Bool, read: Bool, _ completion: @escaping (HealthKitSampleStoreResult<Bool>) -> Void) {
        completion(.success(true))
    }
    
    func replaceCarbEntry(_ oldEntry: StoredCarbEntry, withEntry newEntry: NewCarbEntry, completion: @escaping (CarbStoreResult<StoredCarbEntry>) -> Void) {
        completion(.failure(.notConfigured))
    }
    
    func addCarbEntry(_ entry: NewCarbEntry, completion: @escaping (CarbStoreResult<StoredCarbEntry>) -> Void) {
        completion(.failure(.notConfigured))
    }
    
    func getCarbStatus(start: Date, end: Date?, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<[CarbStatus<StoredCarbEntry>]>) -> Void) {
        completion(.failure(.notConfigured))
    }
    
    func generateDiagnosticReport(_ completion: @escaping (String) -> Void) {
        completion("")
    }
    
    func glucoseEffects<Sample>(of samples: [Sample], startingAt start: Date, endingAt end: Date?, effectVelocities: [LoopKit.GlucoseEffectVelocity]) throws -> [LoopKit.GlucoseEffect] where Sample : LoopKit.CarbEntry {
        return []
    }
    
    func getCarbsOnBoardValues(start: Date, end: Date?, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<[CarbValue]>) -> Void) {
        completion(.success([]))
    }
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        completion(.failure(.notConfigured))
    }
    
    func getTotalCarbs(since start: Date, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        completion(.failure(.notConfigured))
    }
    
    func deleteCarbEntry(_ entry: StoredCarbEntry, completion: @escaping (CarbStoreResult<Bool>) -> Void) {
        completion(.failure(.notConfigured))
    }

    func getGlucoseEffects(start: Date, end: Date?, effectVelocities: [LoopKit.GlucoseEffectVelocity], completion: @escaping (LoopKit.CarbStoreResult<(entries: [LoopKit.StoredCarbEntry], effects: [LoopKit.GlucoseEffect])>) -> Void)
    {
        if let carbHistory, let carbRatioScheduleApplyingOverrideHistory, let insulinSensitivityScheduleApplyingOverrideHistory {
            let foodStart = start.addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)
            let samples = carbHistory.filterDateRange(foodStart, end)
            let carbDates = samples.map { $0.startDate }
            let maxCarbDate = carbDates.max()!
            let minCarbDate = carbDates.min()!
            let carbRatio = carbRatioScheduleApplyingOverrideHistory.between(start: maxCarbDate, end: minCarbDate)
            let insulinSensitivity = insulinSensitivityScheduleApplyingOverrideHistory.quantitiesBetween(start: maxCarbDate, end: minCarbDate)
            let effects = samples.map(
                to: effectVelocities,
                carbRatio: carbRatio,
                insulinSensitivity: insulinSensitivity
            ).dynamicGlucoseEffects(
                from: start,
                to: end,
                carbRatios: carbRatio,
                insulinSensitivities: insulinSensitivity
            )
            completion(.success((entries: samples, effects: effects)))

        } else {
            let fixture: [JSONDictionary] = loadFixture(fixtureToLoad)

            let dateFormatter = ISO8601DateFormatter.localTimeDate()

            return completion(.success(([], fixture.map {
                return GlucoseEffect(startDate: dateFormatter.date(from: $0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue:$0["amount"] as! Double))
            })))
        }
    }
}

extension MockCarbStore {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
    
    var fixtureToLoad: String {
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario computes effects from carb entries, does not used pre-canned effects")
        case .flatAndStable:
            return "flat_and_stable_carb_effect"
        case .highAndStable:
            return "high_and_stable_carb_effect"
        case .highAndRisingWithCOB:
            return "high_and_rising_with_cob_carb_effect"
        case .lowAndFallingWithCOB:
            return "low_and_falling_carb_effect"
        case .lowWithLowTreatment:
            return "low_with_low_treatment_carb_effect"
        case .highAndFalling:
            return "high_and_falling_carb_effect"
        }
    }

    public func loadHistoricCarbEntries(scenario: DosingTestScenario) -> [StoredCarbEntry]? {
        if let url = bundle.url(forResource: scenario.fixturePrefix + "carb_entries", withExtension: "json"),
           let data = try? Data(contentsOf: url)
        {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode([StoredCarbEntry].self, from: data)
        } else {
            return nil
        }
    }

}
