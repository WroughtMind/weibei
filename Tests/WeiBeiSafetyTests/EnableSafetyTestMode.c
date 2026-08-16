#include <stdlib.h>

__attribute__((constructor))
static void weibei_enable_safety_test_mode(void) {
    setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1);
}
