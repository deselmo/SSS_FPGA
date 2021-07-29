#pragma once

#include <unordered_map>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>


namespace acl {
  static double timestamp() {
    timespec a;
    clock_gettime(CLOCK_MONOTONIC, &a);
    return (double(a.tv_nsec) * 1.0e-9) + double(a.tv_sec);
  }

  static double elapsed(const std::pair<double, double> &pair) {
    return 1e3 * double(pair.second - pair.first);
  }

  struct Timer {
    static const std::string format(const std::string &label, double time) {
      std::stringstream ss_time;
      ss_time << std::fixed << std::setprecision(3) << time;
      return label + ": " + ss_time.str() + " ms\n";
    }

    struct Instance {
      Instance(Timer *timer, const std::string &label, bool destructor)
        : timer(timer)
        , label(label)
        , destructor(destructor)
      {}

      double stop() {
        auto &pair = timer->instances[label];
        if(pair.second == -1) {
          pair.second = timestamp();
        }

        return elapsed(pair);
      }

      ~Instance() {
        if(destructor) stop();
      }

      Timer *timer;
      const std::string label;
      const bool destructor;
    };


    Timer(const std::string &label) : stop_first_timer(true) {
      start(label);
    }

    Timer() : stop_first_timer(false) {}

    Timer::Instance start(const std::string &label, const bool destructor=false) {
      labels.push_back(label);
      instances.insert({label, {timestamp(), -1}});
      return Timer::Instance(this, label, destructor);
    }

    bool stop() {
      double end = timestamp();

      double elapsed_ = -1;

      if(stop_first_timer) {
        auto &pair = instances[labels.front()];
        pair.second = end;
        elapsed_ = elapsed(pair);
      }

      for(const std::string &label : labels) {
        auto &pair = instances[label];

        if(pair.second == -1) {
          pair.second = end;
        }
      }

      return elapsed_;
    }

    double stop(const std::string &label) {
      const auto &it = instances.find(label);
      if(it == instances.end()) {
        return -1;
      }

      auto &pair = it->second;
      pair.second = timestamp();
      return elapsed(pair);
    }

    std::string output() {
      std::string _output;

      for(const std::string label : labels) {
        auto &pair = instances[label];
        if(pair.second != -1) {
          _output += format(label, elapsed(pair));
        }
      }

      return _output;
    }

    std::string output(const std::string &label) {
      const auto &it = instances.find(label);
      if(it == instances.end()) {
        return label + ": not found\n";
      }

      auto &pair = it->second;
      if(pair.second == -1) {
        label + ": not terminated\n";
      } else {
        return format(label, elapsed(pair));
      }
    }

    std::string output(const std::vector<std::string> &labels) {
      std::string _output;

      for(const std::string &label : labels) {
        _output += output(label);
      }

      return _output;
    }

  protected:
    std::unordered_map<std::string, std::pair<double, double>> instances;
  private:
    const bool stop_first_timer;
    std::vector<std::string> labels;
  };
}
