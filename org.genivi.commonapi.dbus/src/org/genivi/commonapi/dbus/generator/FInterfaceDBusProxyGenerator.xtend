/* Copyright (C) 2013 BMW Group
 * Author: Manfred Bathelt (manfred.bathelt@bmw.de)
 * Author: Juergen Gehring (juergen.gehring@bmw.de)
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.genivi.commonapi.dbus.generator

import javax.inject.Inject
import org.eclipse.xtext.generator.IFileSystemAccess
import org.franca.core.franca.FAttribute
import org.franca.core.franca.FBroadcast
import org.franca.core.franca.FInterface
import org.franca.core.franca.FMethod
import org.franca.core.franca.FModelElement
import org.genivi.commonapi.core.generator.FrancaGeneratorExtensions
import org.genivi.commonapi.core.deployment.DeploymentInterfacePropertyAccessor

import static com.google.common.base.Preconditions.*


class FInterfaceDBusProxyGenerator {
    @Inject private extension FrancaGeneratorExtensions
    @Inject private extension FrancaDBusGeneratorExtensions

	def generateDBusProxy(FInterface fInterface, IFileSystemAccess fileSystemAccess, DeploymentInterfacePropertyAccessor deploymentAccessor) {
        fileSystemAccess.generateFile(fInterface.dbusProxyHeaderPath, fInterface.generateDBusProxyHeader)
        fileSystemAccess.generateFile(fInterface.dbusProxySourcePath, fInterface.generateDBusProxySource(deploymentAccessor))
	}

    def private generateDBusProxyHeader(FInterface fInterface) '''
        «generateCommonApiLicenseHeader»
        #ifndef «fInterface.defineName»_DBUS_PROXY_H_
        #define «fInterface.defineName»_DBUS_PROXY_H_

        #include <«fInterface.proxyBaseHeaderPath»>
        #include <CommonAPI/DBus/DBusFactory.h>
        #include <CommonAPI/DBus/DBusProxy.h>
        «IF fInterface.hasAttributes»
            #include <CommonAPI/DBus/DBusAttribute.h>
        «ENDIF»
        «IF fInterface.hasBroadcasts»
            #include <CommonAPI/DBus/DBusEvent.h>
        «ENDIF»

        #include <string>

        «fInterface.model.generateNamespaceBeginDeclaration»

        class «fInterface.dbusProxyClassName»: virtual public «fInterface.proxyBaseClassName», virtual public CommonAPI::DBus::DBusProxy {
         public:
            «fInterface.dbusProxyClassName»(
                            const std::string& commonApiAddress,
                            const std::string& interfaceName,
                            const std::string& busName,
                            const std::string& objectPath,
                            const std::shared_ptr<CommonAPI::DBus::DBusProxyConnection>& dbusProxyconnection);

            virtual ~«fInterface.dbusProxyClassName»() { }

            «FOR attribute : fInterface.attributes»
                virtual «attribute.generateGetMethodDefinition»;
            «ENDFOR»

            «FOR broadcast : fInterface.broadcasts»
                virtual «broadcast.generateGetMethodDefinition»;
            «ENDFOR»

            «FOR method : fInterface.methods»

                virtual «method.generateDefinition»;
                «IF !method.isFireAndForget»
                    virtual «method.generateAsyncDefinition»;
                «ENDIF»
            «ENDFOR»
            
            virtual void getOwnVersion(uint16_t& ownVersionMajor, uint16_t& ownVersionMinor) const;

         private:
            «FOR attribute : fInterface.attributes»
                «attribute.dbusClassName» «attribute.dbusClassVariableName»;
            «ENDFOR»

            «FOR broadcast : fInterface.broadcasts»
                «broadcast.dbusClassName» «broadcast.dbusClassVariableName»;
            «ENDFOR»
        };

        «fInterface.model.generateNamespaceEndDeclaration»

        #endif // «fInterface.defineName»_DBUS_PROXY_H_
    '''

    def private generateDBusProxySource(FInterface fInterface, DeploymentInterfacePropertyAccessor deploymentAccessor) '''
        «generateCommonApiLicenseHeader»
        #include "«fInterface.dbusProxyHeaderFile»"
        #include <CommonAPI/types.h>

        «fInterface.model.generateNamespaceBeginDeclaration»
        
        std::shared_ptr<CommonAPI::DBus::DBusProxy> create«fInterface.dbusProxyClassName»(
                            const std::string& commonApiAddress,
                            const std::string& interfaceName,
                            const std::string& busName,
                            const std::string& objectPath,
                            const std::shared_ptr<CommonAPI::DBus::DBusProxyConnection>& dbusProxyConnection) {
            return std::make_shared<«fInterface.dbusProxyClassName»>(commonApiAddress, interfaceName, busName, objectPath, dbusProxyConnection);
        }

        INITIALIZER(register«fInterface.dbusProxyClassName») {
            CommonAPI::DBus::DBusFactory::registerProxyFactoryMethod(«fInterface.name»::getInterfaceId(),
               &create«fInterface.dbusProxyClassName»);
        }

        «fInterface.dbusProxyClassName»::«fInterface.dbusProxyClassName»(
                            const std::string& commonApiAddress,
                            const std::string& interfaceName,
                            const std::string& busName,
                            const std::string& objectPath,
                            const std::shared_ptr<CommonAPI::DBus::DBusProxyConnection>& dbusProxyconnection):
                CommonAPI::DBus::DBusProxy(commonApiAddress, interfaceName, busName, objectPath, dbusProxyconnection)
                «FOR attribute : fInterface.attributes BEFORE ',' SEPARATOR ','»
                    «attribute.generateDBusVariableInit(deploymentAccessor)»
                «ENDFOR»
                «FOR broadcast : fInterface.broadcasts BEFORE ',' SEPARATOR ','»
                    «broadcast.dbusClassVariableName»(*this, "«broadcast.name»", "«broadcast.dbusSignature(deploymentAccessor)»")
                «ENDFOR» {
        }

        «FOR attribute : fInterface.attributes»
            «attribute.generateGetMethodDefinitionWithin(fInterface.dbusProxyClassName)» {
                return «attribute.dbusClassVariableName»;
            }
        «ENDFOR»

        «FOR broadcast : fInterface.broadcasts»
            «broadcast.generateGetMethodDefinitionWithin(fInterface.dbusProxyClassName)» {
                return «broadcast.dbusClassVariableName»;
            }
        «ENDFOR»

        «FOR method : fInterface.methods»
            «method.generateDefinitionWithin(fInterface.dbusProxyClassName)» {
                «method.generateDBusProxyHelperClass»::callMethodWithReply(
                    *this,
                    "«method.name»",
                    "«method.dbusInSignature(deploymentAccessor)»",
                    «method.inArgs.map[name].join('', ', ', ', ', [toString])»
                    callStatus«IF method.hasError»,
                    methodError«ENDIF»
                    «method.outArgs.map[name].join(', ', ', ', '', [toString])»);
            }
            «IF !method.isFireAndForget»
                «method.generateAsyncDefinitionWithin(fInterface.dbusProxyClassName)» {
                    return «method.generateDBusProxyHelperClass»::callMethodAsync(
                        *this,
                        "«method.name»",
                        "«method.dbusInSignature(deploymentAccessor)»",
                        «method.inArgs.map[name].join('', ', ', ', ', [toString])»
                        std::move(callback));
                }
            «ENDIF»
        «ENDFOR»
        
        void «fInterface.dbusProxyClassName»::getOwnVersion(uint16_t& ownVersionMajor, uint16_t& ownVersionMinor) const {
            ownVersionMajor = «fInterface.version.major»;
            ownVersionMinor = «fInterface.version.minor»;
        }

        «fInterface.model.generateNamespaceEndDeclaration»
    '''

    def private dbusClassVariableName(FModelElement fModelElement) {
        checkArgument(!fModelElement.name.nullOrEmpty, 'FModelElement has no name: ' + fModelElement)
        fModelElement.name.toFirstLower + '_'
    }

    def private dbusProxyHeaderFile(FInterface fInterface) {
        fInterface.name + "DBusProxy.h"
    }

    def private dbusProxyHeaderPath(FInterface fInterface) {
        fInterface.model.directoryPath + '/' + fInterface.dbusProxyHeaderFile
    }

    def private dbusProxySourceFile(FInterface fInterface) {
        fInterface.name + "DBusProxy.cpp"
    }

    def private dbusProxySourcePath(FInterface fInterface) {
        fInterface.model.directoryPath + '/' + fInterface.dbusProxySourceFile
    }

    def private dbusProxyClassName(FInterface fInterface) {
        fInterface.name + 'DBusProxy'
    }

    def private generateDBusProxyHelperClass(FMethod fMethod) '''
        CommonAPI::DBus::DBusProxyHelper<CommonAPI::DBus::DBusSerializableArguments<«fMethod.inArgs.map[getTypeName(fMethod.model)].join(', ')»>,
                                         CommonAPI::DBus::DBusSerializableArguments<«IF fMethod.hasError»«fMethod.getErrorNameReference(fMethod.eContainer)»«IF !fMethod.outArgs.empty», «ENDIF»«ENDIF»«fMethod.outArgs.map[getTypeName(fMethod.model)].join(', ')»> >'''

    def private dbusClassName(FAttribute fAttribute) {
        var type = 'CommonAPI::DBus::DBus'

        if (fAttribute.isReadonly)
            type = type + 'Readonly'

        type = type + 'Attribute<' + fAttribute.className + '>'

        if (fAttribute.isObservable)
            type = 'CommonAPI::DBus::DBusObservableAttribute<' + type + '>'

        return type
    }

    def private generateDBusVariableInit(FAttribute fAttribute, DeploymentInterfacePropertyAccessor deploymentAccessor) {
        var ret = fAttribute.dbusClassVariableName + '(*this'

        if (fAttribute.isObservable)
            ret = ret + ', "' + fAttribute.dbusSignalName + '"'

        if (!fAttribute.isReadonly)
            ret = ret + ', "' + fAttribute.dbusSetMethodName + '", "' + fAttribute.dbusSignature(deploymentAccessor) + '", "' + fAttribute.dbusGetMethodName + '")'
        else
            ret = ret + ', "' + fAttribute.dbusSignature(deploymentAccessor) + '", "' + fAttribute.dbusGetMethodName + '")'

        return ret
    }

    def private dbusClassName(FBroadcast fBroadcast) {
        return 'CommonAPI::DBus::DBusEvent<' + fBroadcast.className + '>'
    }
}
