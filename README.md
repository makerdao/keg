# MCD Keg

Streaming payment system for MakerDAO. Payment sources are defined as `Taps` and streamed into the `Keg` for pass-through distribution to the end target(s). Tokens are never at rest inside any of these contracts.

The Keg has pre-defined `Flights` which map human-level strings to distribution targets allocated by percentage.

`seat()` creates a new `flight` distribution.

`revoke()` deletes a distribution.

## Tap Sources

### Tap

The `Tap` is the most common type of payment source. It is fixed rate that `pump()` can be called on it anytime to send any outstanding funds along. The funds are pulled from the surplus buffer (`vow`) via `vat.suck()`. Be aware that `rate` is unbounded and could potentially result in system flop auctions.

### FlapTap

The `FlapTap` is a singleton Tap which forwards a fixed percentage that would otherwise be headed for flap auctions (MKR burner). This can be used to allocate a % of profit to be redirected towards other contracts.