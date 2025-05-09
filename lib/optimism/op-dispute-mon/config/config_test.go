package config

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/ethereum/go-ethereum/common"
)

var (
	validL1EthRpc           = "http://localhost:8545"
	validGameFactoryAddress = common.Address{0x23}
	validRollupRpc          = "http://localhost:8555"
	validSupervisorRpc      = "http://localhost:8999"
)

func validConfig() Config {
	return NewConfig(validGameFactoryAddress, validL1EthRpc, validRollupRpc)
}

func TestValidConfigIsValid(t *testing.T) {
	require.NoError(t, validConfig().Check())
}

func TestL1EthRpcRequired(t *testing.T) {
	config := validConfig()
	config.L1EthRpc = ""
	require.ErrorIs(t, config.Check(), ErrMissingL1EthRPC)
}

func TestGameFactoryAddressRequired(t *testing.T) {
	config := validConfig()
	config.GameFactoryAddress = common.Address{}
	require.ErrorIs(t, config.Check(), ErrMissingGameFactoryAddress)
}

func TestRollupRpcOrSupervisorRpcRequired(t *testing.T) {
	config := validConfig()
	config.RollupRpc = ""
	config.SupervisorRpc = ""
	require.ErrorIs(t, config.Check(), ErrMissingRollupAndSupervisorRpc)
}

func TestRollupRpcNotRequiredWhenSupervisorRpcSet(t *testing.T) {
	config := validConfig()
	config.RollupRpc = ""
	config.SupervisorRpc = validSupervisorRpc
	require.NoError(t, config.Check())
}

func TestSupervisorRpcNotRequiredWhenRollupRpcSet(t *testing.T) {
	config := validConfig()
	config.RollupRpc = validRollupRpc
	config.SupervisorRpc = ""
	require.NoError(t, config.Check())
}

func TestMaxConcurrencyRequired(t *testing.T) {
	config := validConfig()
	config.MaxConcurrency = 0
	require.ErrorIs(t, config.Check(), ErrMissingMaxConcurrency)
}
