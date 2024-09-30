import doctest
import ddd

doctest.testmod(
    ddd, verbose=True, optionflags=doctest.ELLIPSIS | doctest.NORMALIZE_WHITESPACE
)
