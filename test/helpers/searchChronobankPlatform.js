let chronoBankName = "0x4368726f6e6f42616e6b00000000000000000000000000000000000000000000"

// *name* should be bytes32 encoded
var platformsByName = function(account, name, service) {
    var platforms = []

    return Promise.resolve()
    .then(() => service.getPlatformsForUserCount.call(account))
    .then(_numberOfPlatforms => {
        var next = Promise.resolve()
        for (var _idx = 0; _idx < _numberOfPlatforms; ++_idx) {
            (function () {
                let idx = _idx;
                next = next
                .then(() => service.getPlatformForUserAtIndex.call(account, idx))
                .then(_platformMeta => {
                    if (_platformMeta[1] === name) {
                        platforms.push(_platformMeta[0])
                        console.log('found platform by name:', name, _platformMeta[0])
                    }
                })
            })()
        }

        return next
    })
    .then(() => platforms)
}

module.exports.findPlatformsByName = platformsByName
module.exports.ChronoBankPlatformName = chronoBankName
