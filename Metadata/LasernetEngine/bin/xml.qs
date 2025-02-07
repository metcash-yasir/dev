const ElementNode = 1;
const AttributeNode = 2; 
const TextNode = 3; 
const CDATASectionNode = 4; 
const EntityReferenceNode = 5; 
const EntityNode = 6; 
const ProcessingInstructionNode = 7; 
const CommentNode = 8; 
const DocumentNode = 9; 
const DocumentTypeNode = 10; 
const DocumentFragmentNode = 11; 
const NotationNode = 12; 
const BaseNode = 21; 
const CharacterDataNode = 22;

const NODE_ELEMENT					= 1;
const NODE_ATTRIBUTE				= 2;
const NODE_TEXT						= 3;
const NODE_CDATA_SECTION			= 4;
const NODE_ENTITY_REFERENCE			= 5;
const NODE_ENTITY					= 6;
const NODE_PROCESSING_INSTRUCTION	= 7;
const NODE_COMMENT 					= 8;
const NODE_DOCUMENT					= 9;
const NODE_DOCUMENT_TYPE			= 10;
const NODE_DOCUMENT_FRAGMENT		= 11;
const NODE_NOTATION					= 12;
 

const XmlBehaviour_insertAsFirstSibling	= 0;
const XmlBehaviour_insertAsLastSibling	= 1;
const XmlBehaviour_insertAsFirstChild	= 2;
const XmlBehaviour_insertAsLastChild	= 3;
const XmlBehaviour_insertBefore			= 4;
const XmlBehaviour_insertAfter			= 5;
const XmlBehaviour_replace				= 6;
const XmlBehaviour_behaviourUndefined	= 7;
