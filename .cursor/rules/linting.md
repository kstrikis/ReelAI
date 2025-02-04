────────────────────────────
1. Project Configuration (.swiftlint.yml)
────────────────────────────
• Create a .swiftlint.yml file in the root directory of the project. This file lets you customize which rules are enabled or disabled, add additional paths to include/exclude, and set custom thresholds.
• Here’s a sample configuration to get started:

  # .swiftlint.yml
  disabled_rules:  # Specify any rules you want to disable project-wide.
    - identifier_name
    - line_length

  whitelist_rules:  # Optionally, list only the rules you actively want to enforce.
    - colon
    - comma
    - control_statement
    - force_cast  # Example: for enforcing safe casting where applicable.

  opt_in_rules:  # Enable any opt-in rules you consider beneficial.
    - empty_count
    - fatal_error_message

  included:  # Directories and files to include.
    - MyProject/

  excluded:  # Exclude third-party or generated code.
    - Carthage
    - Pods
    - Generated

Customize this file to match our project’s coding style guidelines; check in the repository for potential overrides and rationale behind enabled/disabled rules.

────────────────────────────
2. Integrating SwiftLint Into the Xcode Build Process
────────────────────────────
To enforce linting as part of every build:

• In Xcode, select your project target, then navigate to:
  Build Phases → + → New Run Script Phase
• Add the following script to run SwiftLint:

  if which swiftlint > /dev/null; then
    swiftlint
  else
    echo "warning: SwiftLint not installed, please install from https://github.com/realm/SwiftLint"
  fi

• Place this Run Script Phase as early as possible in the build sequence. While it’s acceptable to run it as a pre-build check, ensure it doesn’t block critical build tasks.
• This script ensures that lint issues are flagged during development. Depending on our configuration, you may choose (or be forced) to treat warnings as errors—so adjust your CI/build settings accordingly.

────────────────────────────
3. Pre-Commit and Continuous Integration (CI)
────────────────────────────
• You’re required to run SwiftLint locally before committing any changes. It’s recommended to use a pre-commit hook:
  - Create a script at .git/hooks/pre-commit (don’t forget to make it executable) that runs SwiftLint and aborts the commit if there are critical linting errors.
  - Example snippet for a Git pre-commit hook:
    #!/bin/sh
    if ! swiftlint; then
     echo "SwiftLint violations were detected. Please fix them before committing."
     exit 1
    fi

• Our CI pipeline is configured to fail if SwiftLint errors are present. Ensure your pull requests have no outstanding lint issues.

────────────────────────────
4. Running SwiftLint Manually
────────────────────────────
• You can run SwiftLint manually from the project’s root directory by simply executing:
  swiftlint
• For more detailed output (or to auto-correct violations if supported), refer to the SwiftLint documentation for additional flags like --fix.

────────────────────────────
5. Addressing and Suppressing Violations
────────────────────────────
• All code must adhere to our linting standards. If a violation is flagged:
  - Correct the issue following our coding conventions.
  - For cases where a particular rule is not applicable or causes false positives, disable it inline using comments:
    // swiftlint:disable <rule_identifier>
    … 
    // swiftlint:enable <rule_identifier>
• Avoid over-suppressing rules; any exceptions should be well-documented in the code and in our project documentation.

────────────────────────────
6. Ongoing Maintenance and Updates
────────────────────────────
• As the project evolves, periodically review the .swiftlint.yml configuration. New rules may be introduced in SwiftLint updates—evaluate these updates and adjust the config to keep our codebase in sync with best practices.
• Document any deviations from the default SwiftLint rules and ensure team consensus for any project-specific exceptions.

────────────────────────────
Summary
────────────────────────────
• SwiftLint is mandatory; it is integrated directly into the build process and enforced through pre-commit hooks and CI.
• Customize and maintain the .swiftlint.yml file to reflect our standards.
• Any lint errors must be resolved before code can be merged.