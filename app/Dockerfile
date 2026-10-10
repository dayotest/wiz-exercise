# Layout: clone the sample todo app (Wiz's "tasky") into this folder, then build.
#   git clone https://github.com/jeffthorne/tasky.git app-src && cp -r app-src/* app/
# Verify the Go version and the assets/ path against that repo before relying on this file.
FROM golang:1.19 AS build
WORKDIR /go/src/tasky
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 go build -o /tmp/tasky

FROM alpine:3.17.0 AS release
WORKDIR /app
COPY --from=build /tmp/tasky .
COPY --from=build /go/src/tasky/assets ./assets

# Required by the exercise: proves how the file got into the image
ARG STUDENT_NAME="CHANGE ME"
RUN echo "${STUDENT_NAME}" > /app/wizexercise.txt

EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
