local Harness = require("support.harness")
local Constants = require("ubermensch.constants")
local Weapons = require("ubermensch.weapons")

Harness.test("all centralized Stock and Kritz mappings", function()
    local stock = {
        29, 211, 663, 796, 805, 885, 894, 903, 912, 961, 970,
        15008, 15010, 15025, 15039, 15050, 15078, 15097,
        15120, 15121, 15122, 15145, 15146,
    }
    for i = 1, #stock do
        Harness.equal(Constants.ITEM_FAMILY[stock[i]], "STOCK")
        Harness.equal(Weapons.classify(stock[i]), "STOCK")
    end
    Harness.equal(Constants.ITEM_FAMILY[35], "KRITZ")
    Harness.equal(Weapons.classify(35), "KRITZ")
end)

Harness.test("unsupported and unknown items fail closed", function()
    Harness.equal(Constants.KNOWN_UNSUPPORTED[411], "QUICK-FIX")
    Harness.equal(Constants.KNOWN_UNSUPPORTED[998], "VACCINATOR")
    Harness.equal(Weapons.classify(411), "UNSUPPORTED")
    Harness.equal(Weapons.classify(998), "UNSUPPORTED")
    Harness.is_nil(Weapons.classify(999999))
    Harness.is_nil(Weapons.classify(29.5))
    Harness.falsy(Weapons.is_supported("UNSUPPORTED"))
end)
