FROM --platform=linux/amd64 golang:1.15

WORKDIR /build
COPY --from=swaggerapi/swagger-ui /usr/share/nginx/html/ /swagger-ui/

ENV PROTOC_VERSION="3.13.0"
ENV PROTO_OS_VERSION="linux-x86_64"
ENV PB_REL="https://github.com/protocolbuffers/protobuf/releases"

RUN mkdir /local \
    && apt-get update \
    && apt-get install python3-distutils -y  \
    && apt-get install python3-apt -y \
    && apt-get install python3-pip -y \
    && apt-get install zip unzip \
    && curl -LO $PB_REL/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-$PROTO_OS_VERSION.zip \
    && unzip protoc-$PROTOC_VERSION-$PROTO_OS_VERSION.zip -d /local \
    && export PATH="$PATH:/local/bin"

RUN go get -u google.golang.org/protobuf/cmd/protoc-gen-go && go install google.golang.org/protobuf/cmd/protoc-gen-go \
    && go get -u google.golang.org/grpc/cmd/protoc-gen-go-grpc && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc \
    && go get -u github.com/gogo/protobuf/protoc-gen-gogofast && go get -u github.com/envoyproxy/protoc-gen-validate

RUN go mod init build && go mod edit -require github.com/grpc-ecosystem/grpc-gateway@v1.16.0 -require github.com/grpc-ecosystem/grpc-gateway/v2@v2.6.0 \
    && go mod download && mkdir http \
    && go get github.com/go-bindata/go-bindata/... \
    && go install \
        github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway \
        github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2 \
    && git clone https://github.com/googleapis/googleapis.git ${GOPATH}/google/googleapis

RUN echo ' \n\
package swagger \n\
import "os" \n\
func GetAsset() func (name string) ([]byte, error)  {return Asset} \n\
func GetAssetInfo() func(name string) (os.FileInfo, error) {return AssetInfo} \n\
func GetAssetDir() func(name string) ([]string, error) {return AssetDir}' >> /var/wrapper.go

RUN  curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python3 >/dev/null \
     && /root/.poetry/bin/poetry --no-interaction install > /dev/null \
     && python3 -m pip install --upgrade pip \
     && curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
     && python3 get-pip.py --force-reinstall \
     && rm get-pip.py \
     && python3 -m pip install grpcio \
     && python3 -m pip install grpcio-tools \
     && pip install protoc-gen-validate \
     && export PYTHONPATH="/usr/lib/python3/dist-packages:/usr/local/lib/python3.7/dist-packages"

CMD mkdir -p python && mkdir -p go && /local/bin/protoc -I ${GOPATH}/src/github.com/envoyproxy/protoc-gen-validate \
       -I ${GOPATH}/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis \
       -I ${GOPATH}/pkg/mod/github.com/grpc-ecosystem/grpc-gateway/v2@v2.6.0 \
       -I /${GOPATH}/google \
       --grpc-gateway_out go \
       --grpc-gateway_opt logtostderr=true \
       --grpc-gateway_opt paths=source_relative \
       --openapiv2_out go \
       --openapiv2_opt logtostderr=true \
       --openapiv2_opt allow_merge=true \
       --openapiv2_opt merge_file_name=api \
       -I /build *.proto --go-grpc_out=go --go_out=go --validate_out="lang=go:go" \
    && if [ -f *.pb.gw.go ]; then \
    cp $(find . -name "*.swagger.json") /swagger-ui/swagger.json \
    && sed -i "s|https://petstore.swagger.io/v2/swagger.json|./swagger.json|g" /swagger-ui/index.html \
    && go-bindata -o /build/swagger/swagger.go -nomemcopy -pkg=swagger -prefix "/swagger-ui/" /swagger-ui \
    && cp /var/wrapper.go /build/swagger/; \
    else rm -rf "go/api.swagger.json"; fi \

    && PYTHONPATH="/usr/lib/python3/dist-packages:/usr/local/lib/python3.7/dist-packages" \
     /root/.poetry/bin/poetry run python -m grpc.tools.protoc \
     -I=. \
     -I ${GOPATH}/pkg/mod/github.com/grpc-ecosystem/grpc-gateway@v1.16.0/third_party/googleapis \
     -I ${GOPATH}/pkg/mod/github.com/grpc-ecosystem/grpc-gateway/v2@v2.6.0 \
     -I ${GOPATH}/src/github.com/envoyproxy/protoc-gen-validate \
     -I /${GOPATH}/google \
     --grpc_python_out=python --python_out=python *.proto
