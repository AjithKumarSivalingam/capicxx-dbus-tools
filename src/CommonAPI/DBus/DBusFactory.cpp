/* Copyright (C) 2013 BMW Group
 * Author: Manfred Bathelt (manfred.bathelt@bmw.de)
 * Author: Juergen Gehring (juergen.gehring@bmw.de)
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
#include "DBusProxy.h"
#include "DBusConnection.h"
#include "DBusFactory.h"
#include "DBusAddressTranslator.h"
#include "DBusServiceRegistry.h"
#include "DBusUtils.h"

#include <algorithm>
#include <cassert>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace CommonAPI {
namespace DBus {

std::unordered_map<std::string, DBusProxyFactoryFunction>* registeredProxyFactoryFunctions_;
std::unordered_map<std::string, DBusAdapterFactoryFunction>* registeredAdapterFactoryFunctions_;


void DBusFactory::registerProxyFactoryMethod(std::string interfaceName, DBusProxyFactoryFunction proxyFactoryMethod) {
    if(!registeredProxyFactoryFunctions_) {
        registeredProxyFactoryFunctions_ = new std::unordered_map<std::string, DBusProxyFactoryFunction>();
    }
    registeredProxyFactoryFunctions_->insert({interfaceName, proxyFactoryMethod});
}

void DBusFactory::registerAdapterFactoryMethod(std::string interfaceName, DBusAdapterFactoryFunction adapterFactoryMethod) {
    if(!registeredAdapterFactoryFunctions_) {
        registeredAdapterFactoryFunctions_ = new std::unordered_map<std::string, DBusAdapterFactoryFunction>();
    }
    registeredAdapterFactoryFunctions_->insert({interfaceName, adapterFactoryMethod});
}



DBusFactory::DBusFactory(std::shared_ptr<Runtime> runtime, const MiddlewareInfo* middlewareInfo) :
                CommonAPI::Factory(runtime, middlewareInfo),
                dbusConnection_(CommonAPI::DBus::DBusConnection::getSessionBus()),
                acquiredConnectionName_("") {
    dbusConnection_->connect();
}


DBusFactory::~DBusFactory() {
}


std::vector<std::string> DBusFactory::getAvailableServiceInstances(const std::string& serviceName,
                                                                   const std::string& domainName) {
    return dbusConnection_->getDBusServiceRegistry()->getAvailableServiceInstances(serviceName, domainName);
}


bool DBusFactory::isServiceInstanceAlive(const std::string& serviceAddress) {
    std::vector<std::string> parts = split(serviceAddress, ':');
    assert(parts[0] == "local");

    std::string interfaceName;
    std::string connectionName;
    std::string objectPath;
    DBusAddressTranslator::getInstance().searchForDBusAddress(serviceAddress, interfaceName, connectionName, objectPath);

    return dbusConnection_->getDBusServiceRegistry()->isServiceInstanceAlive(interfaceName, connectionName, objectPath);
}


bool DBusFactory::isServiceInstanceAlive(const std::string& participantId,
                                         const std::string& serviceName,
                                         const std::string& domainName) {
    std::string serviceAddress = domainName + ":" + serviceName + ":" + participantId;
    return isServiceInstanceAlive(serviceAddress);
}


std::shared_ptr<Proxy> DBusFactory::createProxy(const char* interfaceId,
                                                const std::string& participantId,
                                                const std::string& serviceName,
                                                const std::string& domain) {
    std::string commonApiAddress = domain + ":" + serviceName + ":" + participantId;

    std::string interfaceName;
    std::string connectionName;
    std::string objectPath;

    DBusAddressTranslator::getInstance().searchForDBusAddress(commonApiAddress, interfaceName, connectionName, objectPath);

    if(!registeredProxyFactoryFunctions_) {
        registeredProxyFactoryFunctions_ = new std::unordered_map<std::string, DBusProxyFactoryFunction> {};
    }

    for (auto it = registeredProxyFactoryFunctions_->begin(); it != registeredProxyFactoryFunctions_->end(); ++it) {
        if(it->first == interfaceId) {
            return (it->second)(commonApiAddress, interfaceName, connectionName, objectPath, dbusConnection_);
        }
    }

    return NULL;
}

std::shared_ptr<StubAdapter> DBusFactory::createAdapter(std::shared_ptr<StubBase> stubBase,
                                                        const char* interfaceId,
                                                        const std::string& participantId,
                                                        const std::string& serviceName,
                                                        const std::string& domain) {
    assert(dbusConnection_->isConnected());

    std::string commonApiAddress = domain + ":" + serviceName + ":" + participantId;

    std::string interfaceName;
    std::string connectionName;
    std::string objectPath;

    DBusAddressTranslator::getInstance().searchForDBusAddress(commonApiAddress, interfaceName, connectionName, objectPath);

    if(acquiredConnectionName_ == "") {
        dbusConnection_->requestServiceNameAndBlock(connectionName);
        acquiredConnectionName_ = connectionName;
    } else if (acquiredConnectionName_ != connectionName) {
        return NULL;
    }

    if(!registeredAdapterFactoryFunctions_) {
        registeredAdapterFactoryFunctions_ = new std::unordered_map<std::string, DBusAdapterFactoryFunction> {};
    }

    for (auto it = registeredAdapterFactoryFunctions_->begin(); it != registeredAdapterFactoryFunctions_->end(); ++it) {
        if(it->first == interfaceId) {
            std::shared_ptr<DBusStubAdapter> dbusStubAdapter =  (it->second)(commonApiAddress, interfaceName, connectionName, objectPath, dbusConnection_, stubBase);
            dbusStubAdapter->init();
            return dbusStubAdapter;
        }
    }

    return NULL;
}


} // namespace DBus
} // namespace CommonAPI