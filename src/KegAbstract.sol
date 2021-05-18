// SPDX-License-Identifier: AGPL-3.0-or-later
// KegAbstract.sol

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

pragma solidity >=0.5.12;
pragma experimental ABIEncoderV2;

struct Pint {
    address bum;
    uint256 share;
}

struct Flight {
    address gem;
    Pint[] pints;
}

interface KegAbstract {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function stopped() external view returns (uint256);
    function stop() external;
    function start() external;
    function token() external view returns (address);
    function exists(bytes32 flight) external view returns (bool);
    function gems(bytes32 flight) external view returns (address);
    function pints(bytes32 flight) external view returns (Pint[] memory);
    function pour(bytes32 flight, uint256 rad) external;
    function seat(bytes32 flight, address gem, address[] calldata bums, uint256[] calldata shares) external;
    function revoke(bytes32 flight) external;
}
