// SPDX-License-Identifier: AGPL-3.0-or-later
// Keg.sol

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

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "dss-interfaces/ERC/GemAbstract.sol";

// Preset ratio payout system for streaming payments
contract Keg {

    struct Flight {
        address gem;
        Pint[] pints;
    }

    struct Pint {
        address bum;   // Who to pay
        uint256 share; // The fraction of the total amount to pay out [wad]
    }

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "Keg/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external auth { stopped = 1; emit Stop(); }
    function start() external auth { stopped = 0; emit Start(); }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    // Define payout ratios
    mapping (bytes32 => Flight) internal flights;       // The Flight definitions

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Start();
    event Stop();
    event Pour(address indexed usr, uint256 amount);
    event Seat(bytes32 indexed flight);
    event Revoke(bytes32 indexed flight);

    // --- Init ---
    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---

    // Pre-authorize a flight distribution of funds
    function seat(bytes32 flight, address gem, address[] calldata bums, uint256[] calldata shares) external auth {
        require(bums.length == shares.length, "Keg/unequal-bums-and-shares");
        require(bums.length > 0, "Keg/zero-bums");
        require(gem != address(0), "Keg/no-address-0");

        // Pint shares need to add up to 100%
        uint256 total = 0;
        for (uint256 i = 0; i < bums.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            total = add(total, shares[i]);
            flights[flight].gem = gem;
            flights[flight].pints.push(Pint(bums[i], shares[i]));
        }
        require(total == WAD, "Keg/invalid-flight");
        emit Seat(flight);
    }

    // Deauthorize a flight
    function revoke(bytes32 flight) external auth {
        require(flights[flight].gem != address(0), "Keg/flight-not-set");
        delete flights[flight];
        emit Revoke(flight);
    }

    // --- External ---

    // Sends out funds according to the pre-authorized flight
    function pour(bytes32 flight, uint256 wad) external stoppable {
        address gem = flights[flight].gem;
        Pint[] memory pints = flights[flight].pints;

        require(gem != address(0), "Keg/flight-not-set");

        uint256 suds = 0;
        for (uint256 i = 0; i < pints.length; i++) {
            Pint memory pint = pints[i];
            uint256 sud;
            if (i != pints.length - 1) {
                // Otherwise use the share amount
                sud = mul(wad, pint.share) / WAD;
            } else {
                // Add whatevers left over to the last mug to account for rounding errors
                sud = sub(wad, suds);
            }
            suds = add(suds, sud);

            emit Pour(pint.bum, sud);

            require(GemAbstract(gem).transferFrom(msg.sender, address(pint.bum), sud), "Keg/transfer-failure");
        }
    }

    // Flight lookups
    function exists(bytes32 flight) external view returns (bool) {
        return flights[flight].gem != address(0);
    }
    function gems(bytes32 flight) external view returns (address) {
        return flights[flight].gem;
    }
    function pints(bytes32 flight) external view returns (Pint[] memory) {
        return flights[flight].pints;
    }

}
