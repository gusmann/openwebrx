from owrx.reporting.reporter import Reporter
from owrx.config import Config
from owrx.property import PropertyDeleted
import json
import threading
import time
from elasticsearch_dsl import Index, Search, connections
from elasticsearch_dsl import Document, DateRange, Keyword, Range

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
                "elastic_api_key",
                "elastic_client_id",
                "elastic_use_ssl",
            ).wire(self._reconnect),
        ]

    def _getClient(self) -> Elasticsearch:
        pm = Config.get()

        # Prepare authentication
        auth_params = {}
        if "elastic_api_key" in pm:
            auth_params["api_key"] = pm["elastic_api_key"]
        elif "elastic_user" in pm and "elastic_password" in pm:
            auth_params["http_auth"] = (pm["elastic_user"], pm["elastic_password"])

        client = connections.create_connection(
            hosts=pm["elastic_host"],
            use_ssl=pm["elastic_use_ssl"],
            verify_certs=False,
            **auth_params
        )

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
