from owrx.reporting.reporter import Reporter
from owrx.config import Config
from owrx.property import PropertyDeleted
import json
import threading
import time
from elasticsearch import Elasticsearch

import logging

logger = logging.getLogger(__name__)


class ElasticReporter(Reporter):
    DEFAULT_INDEX = "openwebrx-decodes"

    def __init__(self):
        pm = Config.get()
        self.topic = self.DEFAULT_TOPIC
        self.client = self._getClient()
        self.subscriptions = [
            pm.wireProperty("elastic_topic", self._setTopic),
            pm.filter(
                "elastic_host",
                "elastic_user",
                "elastic_password",
                "elastic_client_id",
                "elastic_use_ssl",
            ).wire(self._reconnect),
        ]

    def _getClient(self):
        pm = Config.get()
        clientId = pm["elastic_client_id"] if "elastic_client_id" in pm else ""
        client = Client(clientId)

        if "elastic_user" in pm and "elastic_password" in pm:
            client.username_pw_set(pm["elastic_user"], pm["elastic_password"])

        port = 1883
        if pm["elastic_use_ssl"]:
            client.tls_set()
            port = 8883

        parts = pm["elastic_host"].split(":")
        host = parts[0]
        if len(parts) > 1:
            port = int(parts[1])

        try:
            client.connect(host=host, port=port)
        except:
            logger.exception("Exception connecting to elastic server")

        threading.Thread(target=client.loop_forever).start()

        return client

    def _setTopic(self, topic):
        if topic is PropertyDeleted:
            self.topic = self.DEFAULT_TOPIC
        else:
            self.topic = topic

    def _reconnect(self, *args, **kwargs):
        logger.debug("Reconnecting...")
        old = self.client
        self.client = self._getClient()
        old.disconnect()

    def stop(self):
        self.client.disconnect()
        while self.subscriptions:
            self.subscriptions.pop().cancel()

    def spot(self, spot):
        self.client.publish(self.topic, payload=json.dumps(spot))
