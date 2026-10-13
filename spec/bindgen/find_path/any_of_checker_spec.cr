require "../../spec_helper"

private def run_check(yaml)
  config = Bindgen::FindPath::AnyOfCheck.from_yaml(yaml)
  checker = Bindgen::FindPath::AnyOfChecker.new(config, is_file: true)
  checker.check(__FILE__)
end

describe Bindgen::FindPath::AnyOfChecker do
  it "passes if all checkers pass" do
    run_check(<<-YAML
    any_of:
      - path: PASSES
        contains: "Contains This"
      - path: PASSES
        contains: "Also Contains This"
    YAML
    ).should be_true
  end

  it "passes if first checker passes" do
    run_check(<<-YAML
    any_of:
      - path: PASSES
        contains: "Contains This"
      - path: FAILS
        contains: "Doesn't Contain This"
    YAML
    ).should be_true
  end

  it "passes if later checker passes" do
    run_check(<<-YAML
    any_of:
      - path: FAILS
        contains: "Doesn't Contain This"
      - path: PASSES
        contains: "Contains This"
    YAML
    ).should be_true
  end

  it "fails if all checkers fail" do
    run_check(<<-YAML
    any_of:
      - path: FAILS
        contains: "Doesn't Contain This"
      - path: FAILS
        contains: "Doesn't Contain This Either"
    YAML
    ).should be_false
  end
end
