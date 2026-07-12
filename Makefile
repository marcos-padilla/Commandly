.PHONY: doctor bootstrap build test lint format verify clean open

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

clean:
	./scripts/clean.sh

open:
	@bash -c 'source ./scripts/common.sh; export_developer_dir; APP="$${DEVELOPER_DIR%/Contents/Developer}"; open -a "$${APP}" Commandly.xcodeproj'
