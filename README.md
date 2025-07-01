# Diamante Mine

## Overview

A smart contract for a mini-app that allows users to "mine" the `DIAMANTE` token. It's designed to create utility for
the `ORO` token by allowing users to spend it to initiate a mining session. In return, users receive `DIAMANTE`, a
fixed-supply token, with the reward amount determined by a pseudo-random mechanism based on network participation.

The contract includes a social referral feature, World ID integration for Sybil resistance, and is built using the UUPS
upgradeable proxy pattern to allow for future logic updates.

## Core Concepts

The contract facilitates a simple mining game loop:

1. **Start Mining**: A user spends `ORO` and provides a World ID proof to begin mining.
2. **Remind a Friend**: When starting mining, the user can nominate another user to "remind." If the reminded user also
   starts a mining session within the mining interval, the original user receives a bonus.
3. **Finish Mining**: After the mining interval has passed, the user can call the `finishMining` function to claim their
   `DIAMANTE` reward.
4. **Reward Calculation**:
   - **Base Reward**: A base reward is calculated with a degree of unpredictability but not random.
   - **Referral Bonus**: If the user's reminded friend successfully starts a mining session, a percentage-based bonus is
     added to the base reward.

## Features

- **UUPS Upgradeable**: Utilizes the ERC1967 UUPS proxy pattern for seamless logic upgrades.
- **World ID Integration**: Ensures that each person can only mine once per day, preventing Sybil attacks.
- **Configurable Parameters**: Contract parameters such as mining fee, reward amounts, and referral bonus percentages
  are configurable by the owner.
- **Mining System**: Users can mine DIAMANTE tokens by paying fees in ORO tokens
- **Referral System**: Users can refer friends and earn bonuses when their referred friends start mining
- **Dynamic Rewards**: Reward levels based on the number of active miners
- **Flexible Referral Data**: Support for encoded call data to enable future features like multiple friend referrals

## Key Functions

- `startMining(root, nullifierHash, proof, userToRemind)`: Initiates a mining session for the `msg.sender`. Requires a
  valid World ID proof and transfers `miningFeeInOro` from the user.
- `finishMining()`: Allows a user to claim their rewards after the `miningInterval` has passed. Calculates the final
  reward (including any referral bonus) and transfers the `DIAMANTE` tokens.

## Development

This project uses [Foundry](https://getfoundry.sh/).

### Setup

```sh
npm install
```

### Build

```sh
forge build
```

### Test

```sh
forge test
```

To view logs, add the `-vvv` flag:

```sh
forge test -vvv
```

### Deploy

The deployment script `script/DeployUpgradeable.s.sol` handles the deployment of the implementation contract and the
ERC1967 proxy.

To deploy to a local Anvil node:

1. Start a local node: `anvil`
2. Run the deployment script:

   ```sh
   forge script script/DeployUpgradeable.s.sol --rpc-url localhost --broadcast
   ```

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Gas Usage

Get a gas report:

```sh
forge test --gas-report
```

### Lint

```sh
npm run lint
```

## Related Efforts

- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## License

This project is licensed under MIT.

## Usage

### Encoded Referral Data

The contract now supports encoded call data for referral addresses, providing flexibility for future features without
requiring ABI changes.

#### Single Friend Referral (Current)

```solidity
// To refer a single friend
address[] memory referralAddresses = new address[](1);
referralAddresses[0] = friendAddress;
bytes memory referralData = abi.encode(referralAddresses);

diamanteMine.startMining(root, nullifier, proof, referralData, amount, permit);
```

#### No Referral

```solidity
// For no referral, pass empty array
address[] memory referralAddresses = new address[](0);
bytes memory referralData = abi.encode(referralAddresses);
// Or simply pass empty bytes
bytes memory referralData = "";

diamanteMine.startMining(root, nullifier, proof, referralData, amount, permit);
```

#### Multiple Friend Referrals (Future)

```solidity
// Future support for multiple referrals
address[] memory referralAddresses = new address[](3);
referralAddresses[0] = friend1;
referralAddresses[1] = friend2;
referralAddresses[2] = friend3;
bytes memory referralData = abi.encode(referralAddresses);

// Currently uses only the first address, but the contract can be extended
// to support multiple referrals without changing the ABI
diamanteMine.startMining(root, nullifier, proof, referralData, amount, permit);
```

### Contract Interface

The main function for starting mining:

```solidity
function startMining(
    uint256 root,
    uint256 nullifierHash,
    uint256[8] calldata proof,
    bytes calldata referralData,  // ABI-encoded address array
    uint256 amount,
    Permit2 memory permit
) external;
```

## Testing

```bash
forge test
```

## Architecture

The contract implements:

- Upgradeable proxy pattern (UUPS)
- OpenZeppelin security patterns
- Permit2 for gasless token approvals
- World ID for sybil resistance

## Deployment

The contract uses a proxy pattern for upgradeability. Deploy the implementation contract and then create a proxy
pointing to it with the appropriate initialization parameters.
