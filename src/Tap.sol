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

    string public flight;   // The target flight in keg
    uint256 public rate;    // The per-second rate of distributing funds [rad]
    uint256 public rho;     // Time of last pump [unix epoch time]

    uint256 constant RAY = 10 ** 27;

    constructor(address keg_, address vow_, string memory flight_, uint256 rate_) public {
        wards[msg.sender] = 1;
        KegAbstract keg__ = keg = KegAbstract(keg_);
        VatAbstract vat__ = vat = VatAbstract(keg__.vat());
        vow = vow_;
        vat__.hope(keg_);
        flight = flight_;
        rate = rate_;
        rho = now;
    }

    // --- Math ---
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, string calldata data) external auth {
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
        uint256 rad = mul(now - rho, rate);
        if (rad > 0) {
            vat.suck(address(vow), address(this), rad);
            keg.pour(flight, rad);
        }
        rho = now;
    }
}