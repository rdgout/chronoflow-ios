import Foundation

public enum BlockParams: Sendable, Equatable, Encodable {
    case flight(FlightParamsView)
    case layover(LayoverParamsView)
    case transfer(TransferParamsView)
    case movementBreak(MovementBreakParamsView)
    case zoneChange(ZoneChangeParamsView)
    case sleep(SleepParamsView)
    case nap(NapParamsView)
    case rest(RestParamsView)
    case avoidLight(AvoidLightParamsView)
    case seekLight(SeekLightParamsView)
    case lightOK(LightOkParamsView)
    case lightNeutral(LightNeutralParamsView)
    case caffeineServing(CaffeineServingParamsView)
    case caffeineOK(CaffeineOkParamsView)
    case caffeineRoutine(CaffeineRoutineParamsView)
    case noCaffeine(NoCaffeineParamsView)
    case note(NoteBlockParamsView)
    case caffeineServingDrinks(CaffeineServingDrinksParamsView)
    case caffeineOKDrinks(CaffeineOkDrinksParamsView)
    case noCaffeineDrinks(NoCaffeineDrinksParamsView)
    case unknown(JSONValue)

    private enum CodingKeys: String, CodingKey { case amount, exception }

    public init(type: BlockType, from decoder: any Decoder) throws {
        switch type {
        case .flight:
            self = .flight(try FlightParamsView(from: decoder))
        case .layover:
            self = .layover(try LayoverParamsView(from: decoder))
        case .transfer:
            self = .transfer(try TransferParamsView(from: decoder))
        case .movementBreak:
            self = .movementBreak(try MovementBreakParamsView(from: decoder))
        case .zoneChange:
            self = .zoneChange(try ZoneChangeParamsView(from: decoder))
        case .sleep:
            self = .sleep(try SleepParamsView(from: decoder))
        case .nap:
            self = .nap(try NapParamsView(from: decoder))
        case .rest:
            self = .rest(try RestParamsView(from: decoder))
        case .avoidLight:
            self = .avoidLight(try AvoidLightParamsView(from: decoder))
        case .seekLight:
            self = .seekLight(try SeekLightParamsView(from: decoder))
        case .lightOK:
            self = .lightOK(try LightOkParamsView(from: decoder))
        case .lightNeutral:
            self = .lightNeutral(try LightNeutralParamsView(from: decoder))
        case .caffeineServing:
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let drinks = (try? container.decode(JSONObject.self, forKey: .amount)) != nil
            if drinks {
                self = .caffeineServingDrinks(try CaffeineServingDrinksParamsView(from: decoder))
            } else {
                self = .caffeineServing(try CaffeineServingParamsView(from: decoder))
            }
        case .caffeineOK:
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let drinks = (try? container.decode(JSONObject.self, forKey: .amount)) != nil
            if drinks {
                self = .caffeineOKDrinks(try CaffeineOkDrinksParamsView(from: decoder))
            } else {
                self = .caffeineOK(try CaffeineOkParamsView(from: decoder))
            }
        case .caffeineRoutine:
            self = .caffeineRoutine(try CaffeineRoutineParamsView(from: decoder))
        case .noCaffeine:
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let exception = try container.decodeIfPresent(JSONObject.self, forKey: .exception)
            let drinks = exception?["amount"]?.object != nil
            if drinks {
                self = .noCaffeineDrinks(try NoCaffeineDrinksParamsView(from: decoder))
            } else {
                self = .noCaffeine(try NoCaffeineParamsView(from: decoder))
            }
        case .note:
            self = .note(try NoteBlockParamsView(from: decoder))
        case .unknown:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .flight(let value): try value.encode(to: encoder)
        case .layover(let value): try value.encode(to: encoder)
        case .transfer(let value): try value.encode(to: encoder)
        case .movementBreak(let value): try value.encode(to: encoder)
        case .zoneChange(let value): try value.encode(to: encoder)
        case .sleep(let value): try value.encode(to: encoder)
        case .nap(let value): try value.encode(to: encoder)
        case .rest(let value): try value.encode(to: encoder)
        case .avoidLight(let value): try value.encode(to: encoder)
        case .seekLight(let value): try value.encode(to: encoder)
        case .lightOK(let value): try value.encode(to: encoder)
        case .lightNeutral(let value): try value.encode(to: encoder)
        case .caffeineServing(let value): try value.encode(to: encoder)
        case .caffeineOK(let value): try value.encode(to: encoder)
        case .caffeineRoutine(let value): try value.encode(to: encoder)
        case .noCaffeine(let value): try value.encode(to: encoder)
        case .note(let value): try value.encode(to: encoder)
        case .caffeineServingDrinks(let value): try value.encode(to: encoder)
        case .caffeineOKDrinks(let value): try value.encode(to: encoder)
        case .noCaffeineDrinks(let value): try value.encode(to: encoder)
        case .unknown(let value): try value.encode(to: encoder)
        }
    }
}

extension BlockView {
    public var isSupported: Bool {
        if case .unknown = type { return false }
        if case .unknown = lane { return false }
        return true
    }
}

extension PlanView {
    public var renderableBlocks: [BlockView] { blocks.filter(\.isSupported) }
}
