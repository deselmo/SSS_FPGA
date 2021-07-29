#pragma once

#define __CL_ENABLE_EXCEPTIONS

#include <acl/utils.hpp>
#include <acl/timer.hpp>
#include <acl/shared_buffer.hpp>
#include <AOCLUtils/options.h>

void cleanup() {}

namespace acl {
  using Options = aocl_utils::Options;
}
