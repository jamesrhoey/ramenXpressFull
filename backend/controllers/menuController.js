const Menu = require('../models/menu');
const Inventory = require('../models/inventory');
const Settings = require('../models/settings');

// Get all menu items with inventory information based on ingredients
const getAllMenu = async (req, res) => {
  try {
    const menuItems = await Menu.find({});
    
    // Enrich menu items with inventory information based on ingredients
    const enrichedMenuItems = await Promise.all(
      menuItems.map(async (menuItem) => {
        let stockQuantity = null;
        let stockStatus = 'in stock';
        
        // Check if menu item has ingredients
        if (menuItem.ingredients && menuItem.ingredients.length > 0) {
          let minAvailablePortions = Infinity;
          let hasOutOfStockIngredient = false;
          let hasLowStockIngredient = false;
          
          // Check each ingredient's availability
          for (const ingredient of menuItem.ingredients) {
            const inventoryItem = await Inventory.findOne({ name: ingredient.inventoryItem });
            
            if (inventoryItem) {
              // Calculate how many portions can be made with this ingredient
              const availablePortions = Math.floor(inventoryItem.stocks / ingredient.quantity);
              
              // Track the limiting ingredient (lowest available portions)
              if (availablePortions < minAvailablePortions) {
                minAvailablePortions = availablePortions;
              }
              
              // Check if any ingredient is out of stock
              if (inventoryItem.stocks <= 0 || availablePortions <= 0) {
                hasOutOfStockIngredient = true;
              }
              // Check if any ingredient is low stock
              else if (inventoryItem.status === 'low stock' || availablePortions <= 10) {
                hasLowStockIngredient = true;
              }
            } else {
              // If ingredient not found in inventory, assume out of stock
              hasOutOfStockIngredient = true;
              minAvailablePortions = 0;
            }
          }
          
          // Set stock quantity to the maximum number of portions that can be made
          stockQuantity = minAvailablePortions === Infinity ? null : minAvailablePortions;
          
          // Determine overall stock status
          if (hasOutOfStockIngredient || minAvailablePortions <= 0) {
            stockStatus = 'out of stock';
          } else if (hasLowStockIngredient || minAvailablePortions <= 10) {
            stockStatus = 'low stock';
          } else {
            stockStatus = 'in stock';
          }
        } else {
          // Fallback: check for inventory item with menu item name
          const inventoryItem = await Inventory.findOne({ name: menuItem.name });
          if (inventoryItem) {
            stockQuantity = inventoryItem.stocks;
            stockStatus = inventoryItem.status;
          }
        }
        
        return {
          ...menuItem.toObject(),
          stockQuantity: stockQuantity,
          stockStatus: stockStatus,
        };
      })
    );
    
    res.status(200).json({
      success: true,
      count: enrichedMenuItems.length,
      data: enrichedMenuItems
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching menu items',
      error: error.message
    });
  }
};

// Get single menu item by ID
const getMenuById = async (req, res) => {
  try {
    const menuItem = await Menu.findById(req.params.id);
    if (!menuItem) {
      return res.status(404).json({
        success: false,
        message: 'Menu item not found'
      });
    }
    res.status(200).json({
      success: true,
      data: menuItem
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching menu item',
      error: error.message
    });
  }
};

// Get add-ons (menu items with category 'add-ons') with inventory information
const getAddOns = async (req, res) => {
  try {
    const addOns = await Menu.find({ category: 'add-ons' });
    
    // Enrich add-ons with inventory information based on ingredients
    const enrichedAddOns = await Promise.all(
      addOns.map(async (addOn) => {
        let stockQuantity = null;
        let stockStatus = 'in stock';
        
        // Check if add-on has ingredients
        if (addOn.ingredients && addOn.ingredients.length > 0) {
          let minAvailablePortions = Infinity;
          let hasOutOfStockIngredient = false;
          let hasLowStockIngredient = false;
          
          // Check each ingredient's availability
          for (const ingredient of addOn.ingredients) {
            const inventoryItem = await Inventory.findOne({ name: ingredient.inventoryItem });
            
            if (inventoryItem) {
              // Calculate how many portions can be made with this ingredient
              const availablePortions = Math.floor(inventoryItem.stocks / ingredient.quantity);
              
              // Track the limiting ingredient (lowest available portions)
              if (availablePortions < minAvailablePortions) {
                minAvailablePortions = availablePortions;
              }
              
              // Check if any ingredient is out of stock
              if (inventoryItem.stocks <= 0 || availablePortions <= 0) {
                hasOutOfStockIngredient = true;
              }
              // Check if any ingredient is low stock
              else if (inventoryItem.status === 'low stock' || availablePortions <= 10) {
                hasLowStockIngredient = true;
              }
            } else {
              // If ingredient not found in inventory, assume out of stock
              hasOutOfStockIngredient = true;
              minAvailablePortions = 0;
            }
          }
          
          // Set stock quantity to the maximum number of portions that can be made
          stockQuantity = minAvailablePortions === Infinity ? null : minAvailablePortions;
          
          // Determine overall stock status
          if (hasOutOfStockIngredient || minAvailablePortions <= 0) {
            stockStatus = 'out of stock';
          } else if (hasLowStockIngredient || minAvailablePortions <= 10) {
            stockStatus = 'low stock';
          } else {
            stockStatus = 'in stock';
          }
        } else {
          // Fallback: check for inventory item with add-on name (common for simple add-ons)
          const inventoryItem = await Inventory.findOne({ name: addOn.name });
          if (inventoryItem) {
            stockQuantity = inventoryItem.stocks;
            stockStatus = inventoryItem.status;
          }
        }
        
        return {
          ...addOn.toObject(),
          stockQuantity: stockQuantity,
          stockStatus: stockStatus,
        };
      })
    );
    
    res.status(200).json({
      success: true,
      count: enrichedAddOns.length,
      data: enrichedAddOns
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching add-ons',
      error: error.message
    });
  }
};

// Get all menu items with ingredient stock information
const getAllMenuWithStock = async (req, res) => {
  try {
    // Get low stock threshold
    const settings = await Settings.findOne({ key: 'lowStockThreshold' });
    const threshold = settings ? settings.value : 10;
    
    const menuItems = await Menu.find({});
    const menuItemsWithStock = [];
    
    for (const menuItem of menuItems) {
      const menuItemWithStock = {
        ...menuItem.toObject(),
        ingredientsWithStock: [],
        canBeOrdered: true,
        hasOutOfStock: false,
        hasLowStock: false
      };
      
      // Check each ingredient's stock
      for (const ingredient of menuItem.ingredients) {
        const inventoryItem = await Inventory.findOne({ name: ingredient.inventoryItem });
        if (inventoryItem) {
          const stockInfo = {
            inventoryItem: ingredient.inventoryItem,
            requiredQuantity: ingredient.quantity,
            currentStock: inventoryItem.stocks,
            isOutOfStock: inventoryItem.stocks <= 0,
            isLowStock: inventoryItem.stocks > 0 && inventoryItem.stocks <= threshold,
            status: inventoryItem.stocks <= 0 ? 'out of stock' : 
                   inventoryItem.stocks <= threshold ? 'low stock' : 'in stock'
          };
          
          menuItemWithStock.ingredientsWithStock.push(stockInfo);
          
          // Update menu item status
          if (inventoryItem.stocks <= 0) {
            menuItemWithStock.canBeOrdered = false;
            menuItemWithStock.hasOutOfStock = true;
          } else if (inventoryItem.stocks <= threshold) {
            menuItemWithStock.hasLowStock = true;
          }
        } else {
          // Ingredient not found in inventory
          const stockInfo = {
            inventoryItem: ingredient.inventoryItem,
            requiredQuantity: ingredient.quantity,
            currentStock: 0,
            isOutOfStock: true,
            isLowStock: false,
            status: 'not found'
          };
          
          menuItemWithStock.ingredientsWithStock.push(stockInfo);
          menuItemWithStock.canBeOrdered = false;
          menuItemWithStock.hasOutOfStock = true;
        }
      }
      
      menuItemsWithStock.push(menuItemWithStock);
    }
    
    res.status(200).json({
      success: true,
      count: menuItemsWithStock.length,
      data: menuItemsWithStock
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching menu items with stock',
      error: error.message
    });
  }
};

// Validate ingredients against inventory
const validateIngredients = async (ingredients) => {
  const missingIngredients = [];
  const invalidIngredients = [];

  for (const ingredient of ingredients) {
    // Frontend sends 'name' field, backend expects 'inventoryItem'
    const ingredientName = ingredient.name || ingredient.inventoryItem;
    
    // Check if ingredient exists in inventory
    const inventoryItem = await Inventory.findOne({ name: ingredientName });
    
    if (!inventoryItem) {
      missingIngredients.push(ingredientName);
    } else if (ingredient.quantity <= 0) {
      invalidIngredients.push(`${ingredientName}: quantity must be greater than 0`);
    }
  }

  return { missingIngredients, invalidIngredients };
};

// Create new menu item
const createMenu = async (req, res) => {
  try {
    const { name, price, category, ingredients } = req.body;
    let image = req.body.image;
    if (req.file) {
      image = req.file.filename; // Store only the filename
    }
    
    // Validate required fields
    if (!name || !price || !category || !image) {
      return res.status(400).json({
        success: false,
        message: 'Name, price, category, and image are required'
      });
    }

    // Parse ingredients if it's a JSON string
    let parsedIngredients = ingredients;
    if (typeof ingredients === 'string') {
      try {
        parsedIngredients = JSON.parse(ingredients);
      } catch (error) {
        console.error('Error parsing ingredients:', error);
        parsedIngredients = [];
      }
    }

    // Validate ingredients if provided
    if (parsedIngredients && Array.isArray(parsedIngredients) && parsedIngredients.length > 0) {
      const { missingIngredients, invalidIngredients } = await validateIngredients(parsedIngredients);
      
      if (missingIngredients.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Some ingredients are not found in inventory',
          missingIngredients: missingIngredients
        });
      }

      if (invalidIngredients.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Invalid ingredient quantities',
          invalidIngredients: invalidIngredients
        });
      }

      // Convert frontend format to backend format
      const backendIngredients = parsedIngredients.map(ingredient => ({
        inventoryItem: ingredient.name,
        quantity: ingredient.quantity
      }));

      const newMenuItem = new Menu({
        name,
        price,
        category,
        image,
        ingredients: backendIngredients
      });

      const savedMenuItem = await newMenuItem.save();
      
      res.status(201).json({
        success: true,
        message: 'Menu item created successfully',
        data: savedMenuItem
      });
    } else {
      // No ingredients provided
      const newMenuItem = new Menu({
        name,
        price,
        category,
        image,
        ingredients: []
      });

      const savedMenuItem = await newMenuItem.save();
      
      res.status(201).json({
        success: true,
        message: 'Menu item created successfully',
        data: savedMenuItem
      });
    }
  } catch (error) {
    console.error('Error creating menu item:', error);
    res.status(500).json({
      success: false,
      message: 'Error creating menu item',
      error: error.message
    });
  }
};

// Update menu item
const updateMenu = async (req, res) => {
  try {
    const { name, price, category, ingredients } = req.body;
    let image = req.body.image;
    if (req.file) {
      image = req.file.filename; // Store only the filename
    }
    
    // Parse ingredients if it's a JSON string
    let parsedIngredients = ingredients;
    if (typeof ingredients === 'string') {
      try {
        parsedIngredients = JSON.parse(ingredients);
      } catch (error) {
        console.error('Error parsing ingredients:', error);
        parsedIngredients = [];
      }
    }
    
    // Validate ingredients if provided
    if (parsedIngredients && Array.isArray(parsedIngredients) && parsedIngredients.length > 0) {
      const { missingIngredients, invalidIngredients } = await validateIngredients(parsedIngredients);
      
      if (missingIngredients.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Some ingredients are not found in inventory',
          missingIngredients: missingIngredients
        });
      }

      if (invalidIngredients.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Invalid ingredient quantities',
          invalidIngredients: invalidIngredients
        });
      }

      // Convert frontend format to backend format
      const backendIngredients = parsedIngredients.map(ingredient => ({
        inventoryItem: ingredient.name,
        quantity: ingredient.quantity
      }));

      const updatedMenuItem = await Menu.findByIdAndUpdate(
        req.params.id,
        {
          name,
          price,
          category,
          image,
          ingredients: backendIngredients
        },
        { new: true, runValidators: true }
      );

      if (!updatedMenuItem) {
        return res.status(404).json({
          success: false,
          message: 'Menu item not found'
        });
      }

      res.status(200).json({
        success: true,
        message: 'Menu item updated successfully',
        data: updatedMenuItem
      });
    } else {
      // No ingredients provided
      const updatedMenuItem = await Menu.findByIdAndUpdate(
        req.params.id,
        {
          name,
          price,
          category,
          image,
          ingredients: []
        },
        { new: true, runValidators: true }
      );

      if (!updatedMenuItem) {
        return res.status(404).json({
          success: false,
          message: 'Menu item not found'
        });
      }

      res.status(200).json({
        success: true,
        message: 'Menu item updated successfully',
        data: updatedMenuItem
      });
    }
  } catch (error) {
    console.error('Error updating menu item:', error);
    res.status(500).json({
      success: false,
      message: 'Error updating menu item',
      error: error.message
    });
  }
};

// Delete menu item
const deleteMenu = async (req, res) => {
  try {
    const deletedMenuItem = await Menu.findByIdAndDelete(req.params.id);
    
    if (!deletedMenuItem) {
      return res.status(404).json({
        success: false,
        message: 'Menu item not found'
      });
    }

    res.status(200).json({
      success: true,
      message: 'Menu item deleted successfully',
      data: deletedMenuItem
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error deleting menu item',
      error: error.message
    });
  }
};

// Get menu items by category with inventory information based on ingredients
const getMenuByCategory = async (req, res) => {
  try {
    const { category } = req.params;
    const menuItems = await Menu.find({ category });
    
    // Enrich menu items with inventory information based on ingredients
    const enrichedMenuItems = await Promise.all(
      menuItems.map(async (menuItem) => {
        let stockQuantity = null;
        let stockStatus = 'in stock';
        
        // Check if menu item has ingredients
        if (menuItem.ingredients && menuItem.ingredients.length > 0) {
          let minAvailablePortions = Infinity;
          let hasOutOfStockIngredient = false;
          let hasLowStockIngredient = false;
          
          // Check each ingredient's availability
          for (const ingredient of menuItem.ingredients) {
            const inventoryItem = await Inventory.findOne({ name: ingredient.inventoryItem });
            
            if (inventoryItem) {
              // Calculate how many portions can be made with this ingredient
              const availablePortions = Math.floor(inventoryItem.stocks / ingredient.quantity);
              
              // Track the limiting ingredient (lowest available portions)
              if (availablePortions < minAvailablePortions) {
                minAvailablePortions = availablePortions;
              }
              
              // Check if any ingredient is out of stock
              if (inventoryItem.stocks <= 0 || availablePortions <= 0) {
                hasOutOfStockIngredient = true;
              }
              // Check if any ingredient is low stock
              else if (inventoryItem.status === 'low stock' || availablePortions <= 10) {
                hasLowStockIngredient = true;
              }
            } else {
              // If ingredient not found in inventory, assume out of stock
              hasOutOfStockIngredient = true;
              minAvailablePortions = 0;
            }
          }
          
          // Set stock quantity to the maximum number of portions that can be made
          stockQuantity = minAvailablePortions === Infinity ? null : minAvailablePortions;
          
          // Determine overall stock status
          if (hasOutOfStockIngredient || minAvailablePortions <= 0) {
            stockStatus = 'out of stock';
          } else if (hasLowStockIngredient || minAvailablePortions <= 10) {
            stockStatus = 'low stock';
          } else {
            stockStatus = 'in stock';
          }
        } else {
          // Fallback: check for inventory item with menu item name
          const inventoryItem = await Inventory.findOne({ name: menuItem.name });
          if (inventoryItem) {
            stockQuantity = inventoryItem.stocks;
            stockStatus = inventoryItem.status;
          }
        }
        
        return {
          ...menuItem.toObject(),
          stockQuantity: stockQuantity,
          stockStatus: stockStatus,
        };
      })
    );
    
    res.status(200).json({
      success: true,
      count: enrichedMenuItems.length,
      data: enrichedMenuItems
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching menu items by category',
      error: error.message
    });
  }
};

module.exports = {
  getAllMenu,
  getAllMenuWithStock,
  getMenuById,
  getAddOns,
  createMenu,
  updateMenu,
  deleteMenu,
  getMenuByCategory
};
