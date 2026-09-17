local Harness = require("support.harness")
local Constants = require("ubermensch.constants")
local Weapons = require("ubermensch.weapons")

Harness.test("all centralized recognized family mappings", function()
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
    Harness.equal(Constants.ITEM_FAMILY[411], "QF")
    Harness.equal(Weapons.classify(411), "QF")
    Harness.equal(Constants.ITEM_FAMILY[998], "VACC")
    Harness.equal(Weapons.classify(998), "VACC")
end)

Harness.test("family capabilities and preference are explicit", function()
    Harness.truthy(Weapons.is_supported("STOCK"))
    Harness.truthy(Weapons.is_supported("KRITZ"))
    Harness.truthy(Weapons.is_supported("QF"))
    Harness.falsy(Weapons.is_supported("VACC"))
    Harness.truthy(Weapons.is_displayable("VACC"))
    Harness.equal(Weapons.tie_rank("STOCK"), 3)
    Harness.equal(Weapons.tie_rank("KRITZ"), 2)
    Harness.equal(Weapons.tie_rank("QF"), 1)
end)

Harness.test("unknown items fail closed", function()
    Harness.is_nil(Weapons.classify(999999))
    Harness.is_nil(Weapons.classify(29.5))
    Harness.falsy(Weapons.is_supported("UNSUPPORTED"))
    Harness.falsy(Weapons.is_displayable("UNSUPPORTED"))
end)
