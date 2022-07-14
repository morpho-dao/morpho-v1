// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {Errors} from "./Errors.sol";

/// @title WadRayMath.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Library to conduct percentage multiplication inspired by https://github.com/aave/protocol-v2/blob/master/contracts/protocol/libraries/math/WadRayMath.sol.
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /// @dev Multiplies two wad, rounding half up to the nearest wad.
    /// @param a Wad.
    /// @param b Wad.
    /// @return The result of a*b, in wad.
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            if (a == 0 || b == 0) return 0;

            require(a <= (type(uint256).max - HALF_WAD) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

            return (a * b + HALF_WAD) / WAD;
        }
    }

    /// @dev Divides two wad, rounding half up to the nearest wad.
    /// @param a Wad.
    /// @param b Wad.
    /// @return The result of a/b, in wad.
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
            uint256 halfB = b / 2;

            require(a <= (type(uint256).max - halfB) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

            return (a * WAD + halfB) / b;
        }
    }

    /// @dev Multiplies two ray, rounding half up to the nearest ray.
    /// @param a Ray.
    /// @param b Ray.
    /// @return The result of a*b, in ray.
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            if (a == 0 || b == 0) return 0;

            require(a <= (type(uint256).max - HALF_RAY) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

            return (a * b + HALF_RAY) / RAY;
        }
    }

    /// @dev Divides two ray, rounding half up to the nearest ray.
    /// @param a Ray.
    /// @param b Ray.
    /// @return The result of a/b, in ray.
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
            uint256 halfB = b / 2;

            require(a <= (type(uint256).max - halfB) / RAY, Errors.MATH_MULTIPLICATION_OVERFLOW);

            return (a * RAY + halfB) / b;
        }
    }

    /// @dev Casts ray down to wad.
    /// @param a Ray.
    /// @return a casted to wad, rounded half up to the nearest wad.
    function rayToWad(uint256 a) internal pure returns (uint256) {
        unchecked {
            uint256 halfRatio = WAD_RAY_RATIO / 2;
            uint256 result = halfRatio + a;
            require(result >= halfRatio, Errors.MATH_ADDITION_OVERFLOW);

            return result / WAD_RAY_RATIO;
        }
    }

    /// @dev Converts wad up to ray.
    /// @param a Wad.
    /// @return a converted in ray.
    function wadToRay(uint256 a) internal pure returns (uint256) {
        unchecked {
            uint256 result = a * WAD_RAY_RATIO;
            require(result / WAD_RAY_RATIO == a, Errors.MATH_MULTIPLICATION_OVERFLOW);
            return result;
        }
    }
}
