package device

import (
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/simpleiot/simpleiot/data"
	"github.com/simpleiot/simpleiot/db"
	"github.com/simpleiot/simpleiot/msg"
)

// Manager is responsible for maintaining device state, running rules, etc
type Manager struct {
	db        *db.Db
	messenger *msg.Messenger
}

// NewManger creates a new Manager
func NewManger(db *db.Db, messenger *msg.Messenger) *Manager {
	return &Manager{
		db:        db,
		messenger: messenger,
	}
}

// Run manager
func (m *Manager) Run() {
	for {
		devices, err := m.db.Devices()
		if err != nil {
			log.Println("Error getting devices: ", err)
			time.Sleep(10 * time.Second)
			continue
		}
		for _, device := range devices {
			// update device state
			changed := device.UpdateState()
			if changed {
				err := m.db.DeviceSetState(device.ID, device.State.SysState)
				if err != nil {
					log.Println("Error updating device state: ", err)
				}
			}

			for _, ruleID := range device.Rules {
				rule, err := m.db.RuleByID(ruleID)
				if err != nil {
					log.Printf("Error finding rule %v: %v\n", ruleID, err)
					continue
				}

				err = m.runRule(&device, &rule)
				if err != nil {
					log.Println("Error running rule: ", ruleID)
				}
			}
		}

		time.Sleep(1 * time.Second)
	}
}

func uniqueUsers(users []data.User) []data.User {
	found := make(map[uuid.UUID]bool)
	ret := []data.User{}
	for _, u := range users {
		if _, present := found[u.ID]; !present {
			ret = append(ret, u)
		}
	}

	return ret
}

func (m *Manager) runRule(device *data.Device, rule *data.Rule) error {
	if device.State.SysState != data.SysStateOnline {
		// only run rules if device is in online state
		return nil
	}

	active := rule.IsActive(device.State.Ios)
	if active != rule.State.Active {
		state := data.RuleState{Active: active}
		if active {
			// process actions
			if !rule.State.Active && rule.Config.Repeat == 0 {
				for _, a := range rule.Config.Actions {
					if a.Type == data.ActionTypeNotify {
						err := m.notify(rule.Config.Description, device.Desc(), a.Template, device.Groups)
						if err != nil {
							log.Println("Error notifying: ", err)
						}
					}
				}
				state.LastAction = time.Now()
			}
		}

		// store updated state in DB
		err := m.db.RuleUpdateState(rule.ID, state)
		if err != nil {
			log.Println("Error updating rule state: ", err)
		}
	}

	return nil
}

func (m *Manager) notify(ruleDesc, devDesc, template string, groups []uuid.UUID) error {
	// find users for the groups
	var users []data.User
	for _, gID := range groups {
		us, err := m.db.UsersForGroup(gID)
		if err != nil {
			log.Printf("Error getting users for group %v: %v\n", gID, err)
			continue
		}
		users = append(users, us...)
	}

	uniqueUsers := uniqueUsers(users)

	// send notification to all users
	var msg string
	if template == "" {
		msg = fmt.Sprintf("Notification: %v at %v fired", ruleDesc, devDesc)
	} else {
		log.Println("FIXME, notify templates not implemented yet")
	}

	for _, u := range uniqueUsers {
		if u.Phone != "" {
			if m.messenger != nil {
				log.Printf("Sending SMS to %v %v: %v\n", u.FirstName, u.LastName, msg)
				err := m.messenger.SendSMS(u.Phone, msg)
				if err != nil {
					log.Printf("Error sending SMS to %v: %v\n", u.Phone, err)
				}
			}
		}
	}

	return nil
}
