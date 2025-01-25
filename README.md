# battleship.sol

On-chain Battleship implementation. The correctness of the setup is ensured through financial incentives: to start playing, users deposit a certain amount of tokens, which they can claim back upon the game's conclusion. However, if their board is incorrect, the user who cheated will be penalized and will not be able to recover their deposit.

## Installation

### 1. Installing Foundry

1. **Install Foundry using the following command**:

   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   ```

2. **Add Foundry to your PATH** (this should be done automatically, but you can verify it by adding the following line to your `.bashrc` or `.zshrc`):

   ```bash
   export PATH="$HOME/.foundry/bin:$PATH"
   ```

3. **Verify the installation**:
   ```bash
   foundry --version
   ```

### 2. Installing Node.js

Node.js is required for utils

1. **Download and install Node.js** from the [official website](https://nodejs.org/), or install it via your package manager.

   - For **macOS** and **Linux** (via package manager):

     ```bash
     brew install node
     ```

   - For **Windows**, download the installer from the official website.

2. **Verify the installation**:
   ```bash
   node --version
   npm --version
   ```

---

Once both Foundry and Node.js are installed you can run:

```bash
forge build
```

And if you want to use utils:

```bash
npm install
```

## Utils

I've added two scripts to help users interact with the smart contract:

- **generateMerkleTree.js** – generates a Merkle tree from a 2D array and inserts it into `data/input.json`.
- **generateSortedShipCoordinates.js** – generates the sorted ship coordinates required to claim the safe deposit back (it can be done manually, but it would take some time :) ).

Blank input:

```json
[
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
]
```
