# TODOs

This document outlines the immediate tasks and future discussion points for the Diamante mini-app, based on the recent protocol sync.

The priority is shipping the Diamante app to address the decline in daily ORO claims.

## Protocol / Smart Contract

- [ ] **Brian:** Deliver V1 of the `DiamanteMine.sol` contract to unblock the full-stack team.
  - [ ] Implement with a placeholder variable reward amount.
  - [ ] Ensure the ABI and events are stable for front-end integration.
  - [ ] Implement admin controls for withdrawing funds and changing parameters.

## Full-Stack

- [ ] **Steve/Marcus:** Begin integrating the V1 `DiamanteMine.sol` contract with the existing UI skeleton.
- [ ] **Steve/Marcus:** Implement the "Info" tab content as shown in the designs.
- [ ] **Blaze:** Ensure a modal design exists for the referral/boost feature.

## Next Steps

These items require follow-up discussion.

- [ ] **Team:** Discuss the final pseudo-random reward mechanism. The current timestamp-based logic is a placeholder and feels too much like a game of chance.
  - **Action Item:** John to consult with Leighton at the Worldcoin Foundation for guidance on what's acceptable.
  - **Ideas:**
    1. Time since the last max reward was hit (sawtooth pattern).
    2. Based on the number of active miners.
    3. A simple hourly cadence (e.g., rewards are higher at the end of the hour).

- [ ] **Team:** Discuss a long-term upgrade strategy for the contract.
  - **Option A: UUPS Proxy:** More complex upfront, but makes future logic/ABI changes much smoother without losing state.
  - **Option B: Redeploy New Contracts:** Simpler and more secure (immutability), but requires special migration logic (either in-contract or on the front-end) to handle users with in-progress mining sessions during an upgrade.
