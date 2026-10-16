// render.go renders a kurtosis-cdk static_files/**/config.toml template with
// real Go text/template (the same engine Kurtosis's plan.render_templates
// uses) against a fixed JSON data fixture, and writes the result to stdout.
//
// This exists to give the anvil-L2 template branches (S4/S4b of the
// dev-ui-ci-snapshot plan: aggkit/config.toml, agglayer/config.toml,
// zkevm-bridge-service/config.toml) a FAST, hermetic regression check that
// does not require a live kurtosis enclave: check.sh feeds this the
// checked-in testdata/*.json fixtures (captured once from a real anvil-L2
// enclave render, see plans/dev-ui-ci-snapshot/s15-evidence/) and asserts on
// the rendered output.
//
// Usage: go run render.go <template-path> <data-json-path>
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"text/template"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: render.go <template-path> <data-json-path>")
		os.Exit(2)
	}
	tmplPath := os.Args[1]
	dataPath := os.Args[2]

	tmplBytes, err := os.ReadFile(tmplPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reading template: %v\n", err)
		os.Exit(1)
	}
	dataBytes, err := os.ReadFile(dataPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "reading data: %v\n", err)
		os.Exit(1)
	}

	// Kurtosis's real render_templates stringifies numeric Starlark values
	// before handing them to Go's text/template (see the aggkit_version /
	// zkevm_fork_id comments in src/chain/shared/aggkit.star and
	// static_files/agglayer/config.toml:3 -- both templates compare a
	// nominally-numeric field against a STRING literal, e.g.
	// `ne .zkevm_fork_id "9"`, which only type-checks if the field arrives as
	// a Go string). decoder.UseNumber() + stringifyNumbers below reproduces
	// that: numeric leaves (at any nesting depth) become their decimal
	// string form; strings/bools/lists/maps are left alone.
	decoder := json.NewDecoder(bytes.NewReader(dataBytes))
	decoder.UseNumber()
	var raw interface{}
	if err := decoder.Decode(&raw); err != nil {
		fmt.Fprintf(os.Stderr, "parsing data JSON: %v\n", err)
		os.Exit(1)
	}
	data, ok := stringifyNumbers(raw).(map[string]interface{})
	if !ok {
		fmt.Fprintln(os.Stderr, "data JSON root must be an object")
		os.Exit(1)
	}

	tmpl, err := template.New("cfg").Parse(string(tmplBytes))
	if err != nil {
		fmt.Fprintf(os.Stderr, "template parse error: %v\n", err)
		os.Exit(1)
	}

	if err := tmpl.Execute(os.Stdout, data); err != nil {
		fmt.Fprintf(os.Stderr, "template execute error: %v\n", err)
		os.Exit(1)
	}
}

// stringifyNumbers recursively converts every json.Number leaf in a decoded
// JSON value into its decimal string representation, leaving strings, bools,
// nulls, maps and slices otherwise untouched.
func stringifyNumbers(v interface{}) interface{} {
	switch t := v.(type) {
	case json.Number:
		return t.String()
	case map[string]interface{}:
		out := make(map[string]interface{}, len(t))
		for k, val := range t {
			out[k] = stringifyNumbers(val)
		}
		return out
	case []interface{}:
		out := make([]interface{}, len(t))
		for i, val := range t {
			out[i] = stringifyNumbers(val)
		}
		return out
	default:
		return v
	}
}
