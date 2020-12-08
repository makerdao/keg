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

pragma solidity ^0.6.7;

import "dss-interfaces/dss/VatAbstract.sol";

// Keg controls payouts
contract Keg {

    struct Pint {
        address bum;  // Who to pay
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

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Stop ---
    uint256 public stopped;
    function stop() external auth { stopped = 1; emit Stop(); }
    function start() external auth { stopped = 0; emit Start(); }
    modifier stoppable { require(stopped == 0, "Keg/is-stopped"); _; }

    uint256 constant WAD = 10 ** 18;

    VatAbstract public immutable vat;

    // Define payout ratios
    mapping (string => Pint[]) public flights;       // The Pint definitions

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Start();
    event Stop();
    event Pour(address indexed usr, uint256 amount);
    event Seat(string indexed flight);
    event Revoke(string indexed flight);

    constructor(address vat_) public {
        vat = VatAbstract(vat_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // Credits people with rights to withdraw funds from the pool using a preset flight
    function pour(string calldata flight, uint256 rad) external stoppable {
        Pint[] memory pints = flights[flight];

        require(rad > 0, "Keg/rad-zero");
        require(pints.length > 0, "Keg/flight-not-set");       // numPints will be empty when not set
        
        uint256 suds = 0;
        for (uint256 i = 0; i < pints.length; i++) {
            Pint memory pint = pints[i];
            uint256 sud;
            if (i != pints.length - 1) {
                // Otherwise use the share amount
                sud = mul(rad, pints[i].share) / WAD;
            } else {
                // Add whatevers left over to the last mug to account for rounding errors
                sud = sub(rad, suds);
            }
            suds = add(suds, sud);
            vat.move(msg.sender, pint.bum, sud);
            emit Pour(pint.bum, sud);
        }
    }

    // Pre-authorize a flight distribution of funds
    function seat(string calldata flight, address[] calldata bums, uint256[] calldata shares) external auth {
        require(bums.length == shares.length, "Keg/unequal-bums-and-shares");
        require(bums.length > 0, "Keg/zero-bums");

        // Pint shares need to add up to 100%
        uint256 total = 0;
        for (uint256 i = 0; i < bums.length; i++) {
            require(bums[i] != address(0), "Keg/no-address-0");
            total = add(total, shares[i]);
            flights[flight].push(Pint(bums[i], shares[i]));
        }
        require(total == WAD, "Keg/invalid-flight");
        emit Seat(flight);
    }

    // Deauthorize a flight
    function revoke(string calldata flight) external auth {
        require(flights[flight].length > 0, "Keg/flight-not-set");       // pints will be 0 when not set
        for (uint256 i = 0; i < flights[flight].length; i++) {
            delete flights[flight][i];
        }
        emit Revoke(flight);
    }

}