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
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Tap/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external auth { stopped = 1; }
    function start() external auth { stopped = 0; }
    modifier stoppable { require(stopped == 0, "Tap/is-stopped"); _; }

    VatAbstract public immutable vat;
    address public immutable vow;
    KegAbstract public immutable keg;
    DaiJoinAbstract public immutable daiJoin;

    bytes32 public flight;  // The target flight in keg
    uint256 public rate;    // The per-second rate of distributing funds [wad]
    uint256 public rho;     // Time of last pump [unix epoch time]

    uint256 constant RAY = 10 ** 27;

    constructor(KegAbstract keg_, DaiJoinAbstract daiJoin_, address vow_, bytes32 flight_, uint256 rate_) public {
        wards[msg.sender] = 1;
        keg = keg_;
        daiJoin = daiJoin_;
        DaiAbstract dai = DaiAbstract(daiJoin_.dai());
        VatAbstract vat_ = vat = VatAbstract(daiJoin_.vat());
        vow = vow_;
        flight = flight_;
        rate = rate_;
        rho = now;
        vat_.hope(address(daiJoin_));
        dai.approve(address(keg_), uint256(-1));
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
    }
    function file(bytes32 what, uint256 data) external auth {
        require(now == rho, "Tap/rho-not-updated");
        if (what == "rate") rate = data;
        else revert("Tap/file-unrecognized-param");
    }

    function pump() external stoppable {
        require(now >= rho, "Tap/invalid-now");
        uint256 wad = mul(now - rho, rate);
        if (wad > 0) {
            vat.suck(address(vow), address(this), mul(wad, RAY));
            daiJoin.exit(address(this), wad);
            keg.pour(flight, wad);
        }
        rho = now;
    }
}