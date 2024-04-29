package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	agglayerconfig "github.com/0xPolygon/agglayer/config"
	cdkdaconfig "github.com/0xPolygon/cdk-data-availability/config"

	zkevmbridgeserviceconfig "github.com/0xPolygonHermez/zkevm-bridge-service/config"
	zkevmnodeconfig "github.com/0xPolygonHermez/zkevm-node/config"

	"log/slog"
)

type Module string

const (
	ZkevmNode           Module = "zkevm-node"
	ZkevmAggLayer       Module = "zkevm-agglayer"
	CdkDataAvailability Module = "cdk-data-availability"
	ZkevmBridgeService  Module = "zkevm-bridge-service"
)

func main() {
	// Check if the expected number of command-line arguments is provided.
	if len(os.Args) != 2 {
		slog.Info("Usage: dump_zkevm_default_config <directory>")
		os.Exit(1)
	}
	directory := os.Args[1]

	// Dump zkevm components default configurations.
	slog.Info("Dumping current zkevm configurations", "directory", directory)

	if err := dumpDefaultConfig(ZkevmNode, directory); err != nil {
		slog.Error("Unable to dump zkevm-node default config", "err", err)
	}

	if err := dumpDefaultConfig(ZkevmAggLayer, directory); err != nil {
		slog.Error("Unable to dump zkevm-agglayer default config", "err", err)
	}

	if err := dumpDefaultConfig(CdkDataAvailability, directory); err != nil {
		slog.Error("Unable to dump cdk-data-availability default config", "err", err)
	}

	if err := dumpDefaultConfig(ZkevmBridgeService, directory); err != nil {
		slog.Error("Unable to dump zkevm-bridge-service default config", "err", err)
	}
}

// Generic method to dump default configuration file of a zkevm-node/cdk-validium components.
func dumpDefaultConfig(module Module, directory string) error {
	slog.Info("Dumping default config", "module", module)

	// Create default config.
	var cfg interface{}
	var err error
	switch module {
	case ZkevmNode:
		cfg, err = zkevmnodeconfig.Default()
	case ZkevmAggLayer:
		cfg, err = agglayerconfig.Default()
	case CdkDataAvailability:
		cfg, err = cdkdaconfig.Default()
	case ZkevmBridgeService:
		cfg, err = zkevmbridgeserviceconfig.Default()
	default:
		return fmt.Errorf("unsupported module: %s", module)
	}
	if err != nil {
		return fmt.Errorf("unable to create default config: %v", err)
	}

	// Marshal config to JSON.
	cfgJson, err := json.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("unable to marshal config to json: %v", err)
	}

	// Transform the JSON config with jq and format it in TOML with yq.
	cmd := fmt.Sprintf("echo '%s' | jq 'walk(if type == \"object\" and keys_unsorted == [\"Duration\"] then ((.Duration / 1e9 | tostring) + \"s\") else . end) | del(..|nulls)' | yq -t", cfgJson)
	cfgToml, err := exec.Command("bash", "-c", cmd).CombinedOutput()
	if err != nil {
		return fmt.Errorf("unable to execute jq command: %v", err)
	}

	// Save the config in TOML.
	fileName := fmt.Sprintf("%s-config.toml", module)
	filePath := filepath.Join(directory, fileName)
	if err := os.WriteFile(filePath, cfgToml, 0644); err != nil {
		return fmt.Errorf("unable to write config to file: %v", err)
	}
	return nil
}
