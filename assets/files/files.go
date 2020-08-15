package files

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"path"
)

// FileUpdate describes a file that gets updated
type FileUpdate struct {
	Dest     string
	Perm     os.FileMode
	Callback func()
}

// UpdateFiles updates various files in the system
func UpdateFiles(dataDir string) error {
	fileUpdates := []FileUpdate{
		{path.Join(dataDir, "server-cert.pem"), 0644, nil},
		{path.Join(dataDir, "server-key.pem"), 0644, nil},
	}

	for _, fu := range fileUpdates {
		f := path.Base(fu.Dest)
		fBytes := Asset(path.Join("/", f))
		if fBytes == nil {
			return fmt.Errorf("Error opening update for: %v", f)
		}

		fOldBytes, _ := ioutil.ReadFile(fu.Dest)
		if bytes.Compare(fBytes, fOldBytes) != 0 {
			fmt.Println("Updating: ", fu.Dest)
			err := ioutil.WriteFile(fu.Dest, fBytes, fu.Perm)
			if err != nil {
				return fmt.Errorf("Error updating: %v", fu.Dest)
			}
			if fu.Callback != nil {
				fu.Callback()
			}
		}
	}

	return nil
}
