# Porting 179D code to 2019 / 2019 PRM

* openstudio-standards `ASHRAE901PRM2019` is a completely different subclass of Standard, and does not inherit from `ASHRAE901` / `ASHRAE9012019`

ACM179dASHRAE9012007.ancestors.take_while { |k| k != Standard } + [Standard]
=> [ACM179dASHRAE9012007, ASHRAE9012007, ASHRAE901, Standard]

ASHRAE901PRM2019.ancestors.take_while { |k| k != Standard } + [Standard]
=> [ASHRAE901PRM2019, ASHRAE901PRM, (ASHRAEPRMCoolingTower, ASHRAEPRMCoilDX, ASHRAE901PRMFan), Standard]  # In parentheses these are Mixin modules (`include`)

* The 90.1-2019 PRM baseline is, AFAIK, based on App G 2004, and is adjusted by Building Performance Factors (BPF). I am not seeing where these BPF might be stored and applied in openstudio-standards...

* I have trouble following the `user_data` pattern that 90.1 PRM is doing. It's not very clearly documented, and is apparently only used in the test/ folder, but IIUC this is a way to claim exceptions. You can create a bunch of specifically formatted CSVs in your project folder and instruct the PRM instance to load them, convert to json and load into standards database, so that you can apply these exceptions

* TBH, I'm still not 100% clear on why there are distinct, separate ASHRAE 90.1-2019 and an ASHRAE 90.1-2019 PRM classes. I guess the first creates the prototype (model_create_prototype_model) based on that standard version, and the latter is for generating the baseline (test calls `model_create_prm_any_baseline_building`, but really that'd be akin to `model_create_prm_stable_baseline_building`).
    * I guess I'm kinda thrown off by the fact that the `model_create_prm_stable_baseline_building` is defined at the root class `Standard` in Standard.Model.rb, meaning that even if I used 90.1-2019 standard (ASHRAE9012019) I *could* technically call `model_create_prm_any_baseline_building`.

cf https://github.com/NREL/openstudio-standards/blob/72ab197f5f3f84eda2456efa44cee6e9d264176f/lib/openstudio-standards/standards/Standards.Model.rb#L23-L72


## What subclassing would we need?

* The 179D workflow does two things:

1. Use `create_typical` measure to create the proposed. I think that would mean using ASHRAE 90.1-2019 (NON PRM) to do so.
2. Create a baseline from that proposed model.

For 1:

* I think that means we have to subclass that specific class for our 179D specific stuff
    * Track the functions we had overriden in "179d 90.1-2007", and determine 1) if the override is still needed, and 2) if the overrride needs adjustment
    * Determine if the data files (json) we have overriden / extended are still needed or not

For 2:
* Assuming we want the 90.1 2019 **PRM** (stable baseline), that mean we'd probably need to ALSO subclass that one.

And we could end up overriding a Standard method in both subclasses (the prm and non-prm 179D subclass) so they do something different... Complexity would increase for sure.

## Bumping OS SDK / standards version or not

Given the complexity involved in this porting effort, I personally think it'd be shame to say on SDK 3.6.1 / Standards 0.4.1, because that would mean subclassing in a much older version, potentially working around bugs that were already fixed upstream. And the effort to bump to more recent versions would still be consequent once the needs arise.


