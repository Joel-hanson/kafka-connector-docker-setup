FROM apache/kafka:latest

WORKDIR /opt/kafka

EXPOSE 8083

RUN mkdir /opt/kafka/plugins 

COPY plugins.sh .
RUN sh plugins.sh

COPY entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]
CMD ["start"]