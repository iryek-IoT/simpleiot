package data

import (
	"fmt"
	"reflect"
)

// Encode is used to convert a user struct to
// a node.
func Encode(in interface{}) (NodeEdge, error) {
	vIn := reflect.ValueOf(in)
	tIn := reflect.TypeOf(in)

	ret := NodeEdge{Type: tIn.Name()}

	valToPoint := func(t string, v reflect.Value) (Point, error) {
		k := v.Type().Kind()
		switch k {
		case reflect.String:
			return Point{Type: t, Text: v.String()}, nil
		case reflect.Int:
			return Point{Type: t, Value: float64(v.Int())}, nil
		case reflect.Float64:
			return Point{Type: t, Value: v.Float()}, nil
		case reflect.Float32:
			return Point{Type: t, Value: v.Float()}, nil
		case reflect.Bool:
			return Point{Type: t, Value: BoolToFloat(v.Bool())}, nil
		default:
			return Point{}, fmt.Errorf("Unhandled type: %v", k)
		}
	}

	for i := 0; i < tIn.NumField(); i++ {
		sf := tIn.Field(i)
		if pt := sf.Tag.Get("point"); pt != "" {
			p, err := valToPoint(pt, vIn.Field(i))
			if err != nil {
				return ret, err
			}
			ret.Points = append(ret.Points, p)
		} else if et := sf.Tag.Get("edgepoint"); et != "" {
			p, err := valToPoint(et, vIn.Field(i))
			if err != nil {
				return ret, err
			}
			ret.EdgePoints = append(ret.EdgePoints, p)
		} else if nt := sf.Tag.Get("node"); nt != "" {
			if nt == "id" {
				v := vIn.Field(i)
				k := v.Type().Kind()
				if k == reflect.String {
					ret.ID = v.String()
				}
			}
		}
	}

	return ret, nil
}
