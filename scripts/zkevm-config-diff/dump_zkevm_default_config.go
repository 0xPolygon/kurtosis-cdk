package main

import (
	"fmt"
	"os"

	agglayerconfig "github.com/0xPolygon/agglayer/config"
	cdkdaconfig "github.com/0xPolygon/cdk-data-availability/config"

	// TODO: Uncomment the following line once https://github.com/0xPolygonHermez/zkevm-bridge-service/pull/609 gets merged.
	//zkevmbridgeservice "github.com/0xPolygonHermez/zkevm-bridge-service"
	zkevmnodeconfig "github.com/0xPolygonHermez/zkevm-node/config"

	// "github.com/0xPolygon/cdk-validium-node/config"
	"log/slog"

	"github.com/spf13/viper"
)

const (
	configFolder = "default/"

	zkevmNodeDefaultConfigFile           = "zkevm-node-config.toml"
	agglayerDefaultConfigFile            = "zkevm-agglayer-config.toml"
	cdkDataAvailabilityDefaultConfigFile = "cdk-data-availability-config.toml"
	zkevmBridgeServiceDefaultConfigFile  = "zkevm-bridge-service.toml"
)

func main() {
	// Create configuration folder.
	if _, err := os.Stat(configFolder); os.IsNotExist(err) {
		err := os.Mkdir(configFolder, 0755)
		if err != nil {
			slog.Error("Unable to create config directory", "err", err)
		}
		slog.Info("Config directory created", "name", configFolder)
	}

	// Dump default configs.
	if err := dumpDefaultConfig(ZkevmNode, zkevmNodeDefaultConfigFile); err != nil {
		slog.Error("Unable to dump zkevm-node default config", "err", err)
	}

	if err := dumpDefaultConfig(ZkevmAggLayer, agglayerDefaultConfigFile); err != nil {
		slog.Error("Unable to dump zkevm-agglayer default config", "err", err)
	}

	if err := dumpDefaultConfig(CdkDataAvailability, cdkDataAvailabilityDefaultConfigFile); err != nil {
		slog.Error("Unable to dump cdk-data-availability default config", "err", err)
	}

	if err := dumpDefaultConfig(ZkevmBridgeService, zkevmBridgeServiceDefaultConfigFile); err != nil {
		slog.Error("Unable to dump zkevm-bridge-service default config", "err", err)
	}
}

type Module string

const (
	ZkevmNode           Module = "zkevm-node"
	ZkevmAggLayer       Module = "zkevm-agglayer"
	CdkDataAvailability Module = "cdk-data-availability"
	ZkevmBridgeService  Module = "zkevm-bridge-service"
)

// Generic method to dump default configuration file of a zkevm-node/cdk-validium components.
func dumpDefaultConfig(module Module, configFile string) error {
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
			// TODO: Uncomment the following lines once https://github.com/0xPolygonHermez/zkevm-bridge-service/pull/609 gets merged.
			//_, err := zkevmbridgeservice.Default()
			//return err
			return fmt.Errorf("not implemented yet")
		}
	default:
		return fmt.Errorf("unsupported module: %s", module)
	}
	if err := defaultConfigFunc(); err != nil {
		return fmt.Errorf("unable to create default config: %v", err)
	}

	if err := viper.WriteConfigAs(configFolder + configFile); err != nil {
		return fmt.Errorf("unable to write default config file: %v", err)
	}
	return nil
}
