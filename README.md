# Kafka Connector Docker Setup

This repository contains the necessary files to set up a Kafka cluster with Kafka Connect using Docker. It's specifically configured to demonstrate the use of file connectors, but can be easily adapted for other connector types.

## Project Structure

- `docker-compose.yml`: Defines the Kafka and Kafka Connect services
- `Dockerfile`: Custom image definition for Kafka Connect
- `entrypoint.sh`: Script to configure and start Kafka Connect
- `plugins.sh`: Script to set up the necessary connector plugins
- `data/`: Directory for storing input and output files for file connectors
- `custom-plugins/`: Directory for storing custom/external connector plugins

## Prerequisites

- Docker
- Docker Compose

## Getting Started

1. Clone this repository:

   ```bash
   git clone https://github.com/your-username/kafka-connector-docker.git
   cd kafka-connector-docker
   ```

2. Create a `data` directory in the project root:

   ```bash
   mkdir data
   ```

3. Start the Kafka and Kafka Connect services:

   ```bash
   docker-compose up -d
   ```

4. Verify that the services are running:

   ```bash
   docker-compose ps
   ```

## Using File Connectors

### File Source Connector

1. Create a source file:

   ```bash
   echo "This is a test message" > data/source.txt
   ```

2. Create the source connector:

   ```bash
   curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d '{
     "name": "file-source",
     "config": {
       "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
       "file": "/data/source.txt",
       "topic": "file-topic"
     }
   }'
   ```

### File Sink Connector

1. Create the sink connector:

   ```bash
   curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d '{
     "name": "file-sink",
     "config": {
       "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
       "file": "/data/sink.txt",
       "topics": "file-topic"
     }
   }'
   ```

2. Check the output file:

   ```bash
   cat data/sink.txt
   ```

## Verifying the Setup

After setting up your connectors, you can verify that everything is working correctly:

### Checking Topics

Verify if the topic is created:

```bash
docker-compose exec kafka ./opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

You should see `file-topic` in the list of topics.

### Consuming Messages

Verify that messages are being produced to the topic:

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic file-topic --from-beginning
```

This command will display all messages in the `file-topic` from the beginning.

### Checking Connector Status

Use the Kafka Connect REST API to check the status of your connectors:

1. List all connectors:

   ```bash
   curl http://localhost:8083/connectors
   ```

2. Check the status of a specific connector (e.g., file-source):

   ```bash
   curl http://localhost:8083/connectors/file-source/status
   ```

3. Check the offsets of a specific connector:

   ```bash
   curl http://localhost:8083/connectors/file-source/offsets
   ```

These commands will help you verify that your connectors are running correctly and processing data as expected.

## Configuration

- Kafka Connect configuration can be modified in the `docker-compose.yml` file under the `connect` service's `environment` section.
- Additional plugins can be added by modifying the `plugins.sh` script.

## Adding Custom Connector Plugins

While this setup includes the file connector by default, you can easily add other custom connector plugins using Docker volumes:

1. Create a directory for your custom plugins:

   ```bash
   mkdir -p custom-plugins
   ```

2. Add your custom connector JAR files to this directory.

3. Modify the `docker-compose.yml` file to add a volume for the custom plugins. Add the following under the `volumes` section of the `connect` service:

   ```yaml
   volumes:
     - ./data:/data
     - ./custom-plugins:/opt/kafka/custom-plugins
   ```

4. Update the `CONNECT_PLUGIN_PATH` environment variable in the `docker-compose.yml` file:

   ```yaml
   environment:
     # ... other environment variables ...
     CONNECT_PLUGIN_PATH: "/opt/kafka/plugins,/opt/kafka/custom-plugins"
   ```

5. Restart your services:

   ```bash
   docker-compose down
   docker-compose up -d
   ```

6. Verify the plugins:

  ```bash
  curl http://localhost:8083/connector-plugins/
  ```

You will be able to see the connector plugin that was added to the `custom-plugins` folder.

Example: Adding the Aiven JDBC connector:

1. Download the connector JAR from the Aiven JDBC connector releases.
2. Place the JAR file in your `custom-plugins` directory.
3. Restart the services as described above.
4. You should now be able to use the JDBC connector in your Kafka Connect setup.

Remember to check the documentation of any custom connectors you add, as they may require additional configuration or dependencies.

## Troubleshooting

- Check container logs:

  ```bash
  docker-compose logs kafka
  docker-compose logs connect
  ```

- Ensure that the Kafka service is healthy before starting connectors.
- Verify that the necessary topics (config, offset, and status storage topics) are created.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
