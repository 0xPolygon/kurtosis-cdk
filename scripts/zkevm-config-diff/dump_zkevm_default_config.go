package main

import (
	"fmt"
	"os"
	"path/filepath"

	agglayerconfig "github.com/0xPolygon/agglayer/config"
	cdkdaconfig "github.com/0xPolygon/cdk-data-availability/config"

	zkevmbridgeserviceconfig "github.com/0xPolygonHermez/zkevm-bridge-service/config"
	zkevmnodeconfig "github.com/0xPolygonHermez/zkevm-node/config"

	"log/slog"

	"github.com/spf13/viper"
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
		fmt.Println("Usage: dump_zkevm_default_config <directory>")
		os.Exit(1)
	}
	directory := os.Args[1]

	// Dump zkevm components default configurations.
	slog.Info(fmt.Sprintf("Dumping current zkevm configurations in %s...", directory))

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

	var defaultConfigFunc func() error
	switch module {
	case ZkevmNode:
		defaultConfigFunc = func() error {
			_, err := zkevmnodeconfig.Default()
			return err
		}
	case ZkevmAggLayer:
		defaultConfigFunc = func() error {
			_, err := agglayerconfig.Default()
			return err
		}
	case CdkDataAvailability:
		defaultConfigFunc = func() error {
			_, err := cdkdaconfig.Default()
			return err
		}
	case ZkevmBridgeService:
		defaultConfigFunc = func() error {
			_, err := zkevmbridgeserviceconfig.Default()
			return err
		}
	default:
		return fmt.Errorf("unsupported module: %s", module)
	}
	if err := defaultConfigFunc(); err != nil {
		return fmt.Errorf("unable to create default config: %v", err)
	}
	filePath := filepath.Join(directory, fmt.Sprintf("%s-config.toml", module))
	if err := viper.WriteConfigAs(filePath); err != nil {
		return fmt.Errorf("unable to write default config file: %v", err)
	}
	return nil
}
