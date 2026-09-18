.PHONY: doctor bootstrap build test lint format verify boundaries new-module clean open

doctor:
	./scripts/doctor.sh

bootstrap:
	./scripts/bootstrap.sh

build:
	./scripts/build.sh

test:
	./scripts/test.sh

lint:
	./scripts/lint.sh

format:
	./scripts/format.sh

verify:
	./scripts/verify.sh

boundaries:
	./scripts/check-module-boundaries.sh

new-module:
	./scripts/new-module.sh $(NAME)

clean:
	./scripts/clean.sh

open:
	@bash -c 'source ./scripts/common.sh; export_developer_dir; APP="$${DEVELOPER_DIR%/Contents/Developer}"; open -a "$${APP}" Commandly.xcodeproj'
