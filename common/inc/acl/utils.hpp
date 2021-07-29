#pragma once

#include <fstream>
#include <stdexcept>
#include <unistd.h>


#include <CL/cl.hpp>
#include <AOCLUtils/opencl.h>
#include <CL/cl_ext.h>

#ifndef PLATFORM
#define PLATFORM "Intel(R) FPGA SDK for OpenCL(TM)"
#endif

#ifndef BINARY_FILE_NAME
#define BINARY_FILE_NAME "a.aocx"
#endif


typedef cl_int (*clGetProfileDataDevice_fn) (
  cl_device_id device_id,
  cl_program program,
  cl_bool read_enqueue_kernels,
  cl_bool read_auto_enqueued,
  cl_bool clear_counters_after_readback,
  size_t param_value_size,
  void * param_value,
  size_t * param_value_size_ret,
  cl_int * errcode_ret
);


namespace acl {
  cl::Platform _platform;
  std::vector<cl::Device> _devices;
  cl::Device _device;
  cl::Context _context;

  clGetProfileDataDevice_fn get_profile_data_ptr = nullptr;

  bool _cwd_initialized = false;

  bool cwd() {
    if(!_cwd_initialized) {
      char path_c[300];
      ssize_t n = readlink("/proc/self/exe", path_c, 300);
      if(n < 0) throw std::runtime_error("Error: get the executing host's path");
      path_c[n] = '\0';

      std::string path(path_c);
      path = std::string(path.begin(), path.begin() + path.find_last_of("/"));

      if(chdir(path.c_str())) throw std::runtime_error("Error: change the working directory");

      _cwd_initialized = true;
    }

    return _cwd_initialized;
  }

  cl::Platform &platform() {
    if(!_platform()) {
      std::vector<cl::Platform> platforms;
      cl::Platform::get(&platforms);

      for(size_t i=0; i!=platforms.size() && !_platform(); ++i) {
        if(platforms[i].getInfo<CL_PLATFORM_NAME>() == PLATFORM) {
          _platform = platforms[i];
        }
      }

      if(!_platform()) {
        throw cl::Error(1, "Platform not found");
      }
    }

    return _platform;
  }

  std::vector<cl::Device> &devices() {
    if(_devices.empty()) {
      platform().getDevices(CL_DEVICE_TYPE_ALL, &_devices); 
    }

    return _devices;
  }

  cl::Device &device() {
    if(!_device()) {
      _device = devices().front();
    }

    return _device;
  }

  void _oclContextCallback(const char *errinfo, const void *, size_t, void *) {
    printf("Context callback: %s\n", errinfo);
  }

  cl::Context &context() {
    if(!_context()) {
      _context = cl::Context(device(), nullptr, _oclContextCallback);
    }

    return _context;
  }

  cl::CommandQueue queue(bool profiling=true) {
    auto properties = profiling ? CL_QUEUE_PROFILING_ENABLE : 0;
    return cl::CommandQueue(context(), properties);
  }


  std::vector<uint8_t> load_binary(const std::string &binary_file_name) {
    std::vector<uint8_t> bin;
    FILE* fp = fopen(binary_file_name.c_str(), "rb");
    if(fp == 0) {
      return bin;
    }

    fseek(fp, 0, SEEK_END);
    bin = std::vector<uint8_t>(ftell(fp));

    rewind(fp);

    size_t readed = fread((void *) bin.data(), bin.size(), 1, fp);
    fclose(fp);

    if(readed == 0) {
      return std::vector<uint8_t>();
    }

    return bin;
  }


  cl::Program Program(const std::vector<uint8_t> &bin, bool build=true, cl::Context _context=cl::Context(nullptr)) {
    _context = _context() ? _context : context();
    cl::Program _program = cl::Program(_context, devices(), {1, {bin.data(), bin.size()}});
    if(build) {
      _program.build();
    }
    return _program;
  }


  cl::Program Program(std::string binary_file_name, bool build=true, cl::Context _context=cl::Context(nullptr)) {
    cwd();
    binary_file_name += binary_file_name.find(".aocx\0") == std::string::npos ? ".aocx" : "";
    if(access(binary_file_name.c_str(), R_OK) == -1) {
      throw std::runtime_error("Error: the specified binary file does not exist");
    }

    std::vector<uint8_t> bin = load_binary(binary_file_name);
    if(bin.empty()) {
      throw std::runtime_error("Error: reading the binary file");
    }

    return Program(bin, true);
  }


  double elapsed(cl::Event start, cl::Event end) {
    return 1e-6 * double(  end.getProfilingInfo<CL_PROFILING_COMMAND_END>() -
                         start.getProfilingInfo<CL_PROFILING_COMMAND_START>()) ;
  }

  double elapsed(cl::Event event) {
    return elapsed(event, event);
  }

  cl_int profile_autorun_kernels(cl::Program program) {
#ifdef ARCH_DEVICE
  if(!get_profile_data_ptr) {
    get_profile_data_ptr = (clGetProfileDataDevice_fn)
    clGetExtensionFunctionAddressForPlatform(platform()(), "clGetProfileDataDeviceIntelFPGA");
  }

  cl_int err = (get_profile_data_ptr) (device()(), program(), false, true, false, 0, NULL, NULL, NULL);

  if(err) {
    throw cl::Error(err, "Profiling autorun kernels");
  }

  return err;
#else
  return CL_SUCCESS;
#endif
  }
}
