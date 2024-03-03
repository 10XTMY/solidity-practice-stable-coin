1. (Relative Stability) Anchored or Pegged -> $1.00
    1. Chainlink Price Feed
    2. Set a function to exchange ETH & BTC -> $$$
2. Stability Mechanism (Minting): Algorithmic (Decentralised)
    1. People can only mint the stablecoin with enough collateral (coded)
3. Collateral type: Exogenous (Crypto)
    1. wETH
    2. wBTC (wrapped BTC is a little centralised depending on who is onboarding the BTC from ETH)

- calculate health factor function
- set health factor if debt is 0
- use Handler based testing

1. Proper oracle use:
    see libraries folder in src
2. Smart Contract Audit Prep
    read: https://github.com/nascentxyz/simple-security-toolkit/blob/main/audit-readiness-checklist.md


# Invariants and Properties

### Invariant: 
Property of our system that should always hold.

### Property: 

# Symbolic Execution/Formal Verification

# Fuzz/Invariant Testing

Test multiple scenarios at once, supplying random data to your system to try and break it.

Instead of defining variables inside the test function, leave them as parameters and forge test will use all possible input data to test it.

The way the fuzzer picks the "random" data needs to be studied...

### Stateless Fuzzing: Where the state of the previous run is discarded every new run.

### Stateful Fuzzing (Invariant testing): Ending state of previous run considered starting state on next run
* Use invariant_ keyword: function invariant_testAwlaysReturnsZero()
* Contract is StdInvariant
