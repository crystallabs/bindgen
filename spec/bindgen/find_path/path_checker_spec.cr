require "../../spec_helper"

private def run_check(is_file, yaml)
  if is_file
    root = __FILE__
  else
    root = "#{__DIR__}/../.." # Path to spec/
  end

  config = Bindgen::FindPath::PathCheck.from_yaml(yaml)
  checker = Bindgen::FindPath::PathChecker.new(config, is_file)
  checker.check(root)
end

describe Bindgen::FindPath::PathChecker do
  context "is_file: true" do
    context "contains: String, regex: false" do
      it "checks that the file contains the string" do
        # ABSOLUTELY\dCONTAINS\dTHIS
        run_check(
          true,
          <<-YAML
            path: This/Is/Ignored.cr
            contains: "ABSOLUTELY\\\\dCONTAINS\\\\dTHIS"
            YAML
        ).should be_true
      end
    end

    context "contains: String, regex: true" do
      it "checks that the file matches the regex" do
        # Find This Number: 1337
        run_check(
          true,
          <<-YAML
            path: This/Is/Ignored.cr
            contains: "Find This Number: \\\\d+"
            regex: true
            YAML
        ).should be_true

        run_check(
          true,
          <<-YAML
            path: This/Is/Ignored.cr
            contains: "Totally doesn't contain this \\\\d+"
            regex: true
            YAML
        ).should be_false
      end
    end
  end

  context "is_file: false" do
    context "kind: File (implicit)" do
      context "contains: nil" do
        it "checks for the files existence" do
          run_check(
            false,
            <<-YAML
              path: bindgen/find_path/path_checker_spec.cr
              YAML
          ).should be_true

          run_check(
            false,
            <<-YAML
              path: bindgen/find_path/doesnt_exist.cr
              YAML
          ).should be_false
        end
      end

      context "contains: String, regex: false" do
        it "checks that the file contains the string" do
          # ABSOLUTELY\dCONTAINS\dTHIS
          run_check(
            false,
            <<-YAML
              path: bindgen/find_path/path_checker_spec.cr
              contains: "ABSOLUTELY\\\\dCONTAINS\\\\dTHIS"
              YAML
          ).should be_true

          run_check(
            false,
            <<-YAML
              path: spec_helper.cr
              contains: "Totally doesn't contain this string!!"
              YAML
          ).should be_false
        end
      end

      context "contains: String, regex: true" do
        it "checks that the file matches the regex" do
          # Find This Number: 1337
          run_check(
            false,
            <<-YAML
              path: bindgen/find_path/path_checker_spec.cr
              contains: "Find This Number: \\\\d+"
              regex: true
              YAML
          ).should be_true

          run_check(
            false,
            <<-YAML
              path: spec_helper.cr
              contains: "Totally doesn't contain this \\\\d+"
              regex: true
              YAML
          ).should be_false
        end
      end
    end

    context "kind: Directory" do
      it "checks for the directories existence" do
        run_check(
          false,
          <<-YAML
            path: bindgen/find_path
            kind: Directory
            YAML
        ).should be_true

        run_check(
          false,
          <<-YAML
            path: doesnt_exist
            kind: Directory
            YAML
        ).should be_false
      end
    end
  end
end
