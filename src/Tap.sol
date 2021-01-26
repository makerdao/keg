// Tap.sol

// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>

pragma solidity ^0.6.7;

import "dss-interfaces/dss/VatAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";
import "dss-interfaces/dss/DaiJoinAbstract.sol";
import "./KegAbstract.sol";

// A tap can suck funds from the vow to fill the keg at a preset rate.
contract Tap {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "Tap/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external auth { stopped = 1; }
    function start() external auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Tap/is-stopped"); _; }

    // --- Variable ---
    VatAbstract     public immutable vat;
    address         public immutable vow;
    KegAbstract     public immutable keg;
    DaiJoinAbstract public immutable daiJoin;

    bytes32 public flight;  // The target flight in keg
    uint256 public rate;    // The per-second rate of distributing funds [wad]
    uint256 public rho;     // Time of last pump [unix epoch time]

    uint256 constant RAY = 10 ** 27;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 data);
    event File(bytes32 indexed what, uint256 data);


    // --- Init ---
    constructor(KegAbstract keg_, DaiJoinAbstract daiJoin_, address vow_, bytes32 flight_, uint256 rate_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        keg     = keg_;
        daiJoin = daiJoin_;
        vow     = vow_;
        flight  = flight_;
        rate    = rate_;
        rho     = now;
        VatAbstract vat_ = vat = VatAbstract(daiJoin_.vat());
        DaiAbstract dai  = DaiAbstract(daiJoin_.dai());

        vat_.hope(address(daiJoin_));
        require(dai.approve(address(keg_), uint256(-1)), "Tap/dai-approval-failure");
    }

    // --- Math ---
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, bytes32 data) external auth {
        require(now == rho, "Tap/rho-not-updated");
        if (what == "flight") flight = data;
        else revert("Tap/file-unrecognized-param");

        emit File(what, data);
    }
    function file(bytes32 what, uint256 data) external auth {
        require(now == rho, "Tap/rho-not-updated");
        if (what == "rate") rate = data;
        else revert("Tap/file-unrecognized-param");

        emit File(what, data);
    }

    // --- External ---
    function pump() external stoppable {
        require(now > rho, "Tap/invalid-now");
        uint256 wad = mul(now - rho, rate);
        rho = now;

        vat.suck(address(vow), address(this), mul(wad, RAY));
        daiJoin.exit(address(this), wad);
        keg.pour(flight, wad);
    }
}