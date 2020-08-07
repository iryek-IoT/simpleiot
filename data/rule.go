package data

import (
	"time"

	"github.com/google/uuid"
)

// Condition defines parameters to look for in a sample. Either SampleType or SampleID
// (or both) can be set. They can't both be "".
type Condition struct {
	SampleType string  `json:"sampleType"`
	SampleID   string  `json:"sampleID"`
	Value      float64 `json:"value"`
	Operator   string  `json:"operator"`
}

// ActionType defines the type of action to take
type ActionType string

// define valid action types
const (
	ActionTypeNotify = "notify"
)

// Action defines actions that can be taken if a rule is active.
// Template can optionally be used to customize the message that is sent and
// uses Io Type or IDs to fill in the values. Example might be:
// JamMonitoring: Alert: {{ description }} is in ALARM state with tank level of {{ tankLevel }}.
type Action struct {
	Type     ActionType `json:"type"`
	Template string     `json:"template"`
}

// RuleConfig contains parts of the rule that a users changes
type RuleConfig struct {
	Description string        `json:"description"`
	DeviceID    string        `json:"deviceID"`
	Conditions  []Condition   `json:"conditions"`
	Actions     []Action      `json:"actions"`
	Repeat      time.Duration `json:"repeat"`
}

// RuleState contains parts of a rule that the system changes
type RuleState struct {
	Active     bool      `json:"active"`
	LastAction time.Time `json:"lastAction"`
}

// Rule defines a conditions and actions that are run if condition is true. Global indicates
// the rule applies to all Devices. The rule config and state is separated so we can make updates
// to the Rule without config affecting state, and state affecting config as these are typically
// done by two different entities.
type Rule struct {
	ID     uuid.UUID  `json:"id" boltholdKey:"ID"`
	Config RuleConfig `json:"config"`
	State  RuleState  `json:"state"`
}

// IsActive checks if the rule is active against a data sample set
func (r *Rule) IsActive(ios []Sample) bool {
	active := true
	// any of the below conditions can turn active false
	for _, c := range r.Config.Conditions {
		for _, io := range ios {
			if c.SampleType != "" && c.SampleType != io.Type {
				continue
			}
			if c.SampleID != "" && c.SampleID != io.ID {
				continue
			}

			// rule matches IO, no check condition
			switch c.Operator {
			case ">":
				if io.Value <= c.Value {
					active = false
					break
				}
			case "<":
				if io.Value >= c.Value {
					active = false
					break
				}
			case "=":
				if io.Value != c.Value {
					active = false
					break
				}
			}
		}
		if !active {
			break
		}
	}
	return active
}
