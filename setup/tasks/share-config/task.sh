# The answers, put where another machine can pick them up, and the address of
# them kept as an answer — see share_config in lib.sh, which is also the one
# place that knows this must never fail an installation that has already worked.
#
# It guards itself: the simulation is inside share_config, because there it can
# still answer with an address and leave the page at the end of the run with
# something on it.

share_config
