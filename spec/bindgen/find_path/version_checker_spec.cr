require "../../spec_helper"

private def run_check(yaml)
  config = Bindgen::FindPath::VersionCheck.from_yaml(yaml)
  checker = Bindgen::FindPath::VersionChecker.new(config)

  Dir.cd "#{__DIR__}/fixture" do
    checker.check("tool")
    checker.check("tool-1.0")
    checker.check("tool-2.0")
  end

  checker
end

describe Bindgen::FindPath::VersionChecker do
  context "if none match" do
    it "finds nothing due to broken regex" do
      subject = run_check(<<-YAML
        regex: "-failing-"
        YAML
      )

      subject.best_candidate.should eq(nil)
      subject.candidates.empty?.should be_true
    end

    it "finds nothing due to min version" do
      subject = run_check(<<-YAML
        min: "3.0"
        YAML
      )

      subject.best_candidate.should eq(nil)
      subject.candidates.empty?.should be_true
    end

    it "finds nothing due to max version" do
      subject = run_check(<<-YAML
        max: "0.5"
        YAML
      )

      subject.best_candidate.should eq(nil)
      subject.candidates.empty?.should be_true
    end
  end

  context "prefer: Highest (implicit)" do
    it "returns the highest versioned match" do
      subject = run_check(<<-YAML
        min: 1.0
        YAML
      )

      subject.best_candidate.should eq("tool-2.0")
    end
  end

  context "prefer: Lowest" do
    it "returns the lowest versioned match" do
      subject = run_check(<<-YAML
        prefer: lowest
        YAML
      )

      subject.best_candidate.should eq("tool-1.0")
    end
  end

  context "fallback: Fail (implicit)" do
    it "fails the match" do
      subject = run_check("{ }")

      subject.best_candidate.should eq("tool-2.0")
      subject.candidates.should eq([
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
      ])
    end
  end

  context "fallback: Accept" do
    it "adds the candidate as lowest priority" do
      subject = run_check(<<-YAML
        fallback: Accept
        YAML
      )

      subject.best_candidate.should eq("tool-2.0")
      subject.candidates.should eq([
        {" ", "tool"},
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
      ])
    end

    it "adds the candidate as highest priority" do
      subject = run_check(<<-YAML
        fallback: Accept
        prefer: Lowest
        YAML
      )

      subject.best_candidate.should eq("tool-1.0")
      subject.candidates.should eq([
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
        {"~", "tool"},
      ])
    end
  end

  context "fallback: Prefer" do
    it "adds the candidate as highest priority" do
      subject = run_check(<<-YAML
        fallback: Prefer
        YAML
      )

      subject.best_candidate.should eq("tool")
      subject.candidates.should eq([
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
        {"~", "tool"},
      ])
    end

    it "adds the candidate as lowest priority" do
      subject = run_check(<<-YAML
        prefer: Lowest
        fallback: Prefer
        YAML
      )

      subject.best_candidate.should eq("tool")
      subject.candidates.should eq([
        {" ", "tool"},
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
      ])
    end
  end

  context "command: String" do
    it "calls the command for each candidate" do
      subject = run_check(<<-YAML
        command: "cat '%'"
        regex: "^VERSION=(.*)"
        YAML
      )

      subject.best_candidate.should eq("tool")
      subject.candidates.should eq([
        {"1.0", "tool-1.0"},
        {"2.0", "tool-2.0"},
        {"3.0", "tool"},
      ])
    end
  end
end
