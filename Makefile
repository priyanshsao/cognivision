.PHONY: proto fmt

fmt:
	gofmt -w gateway/
	
	ruff format inference/

proto:
	protoc \
		--proto_path=. \
		--go_out=gateway/ \
		--go_opt=paths=source_relative \
		proto/define.proto

	protoc \
		--python_out=inference/ \
		--pyi_out=inference/ \
		proto/define.proto